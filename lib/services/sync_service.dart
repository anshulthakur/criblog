import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'drive_service.dart';
import 'database.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';

class SyncService {
  final DriveService _driveService = DriveService();
  final DatabaseService _dbService = DatabaseService();
  bool _isSyncing = false; // Prevent concurrent syncs

  Future<bool> get isAuthorized async => await _driveService.isAuthorized;
  Future<String?> get currentUserEmail async => await _driveService.currentUserEmail;

  Future<void> sync({bool forcePull = false}) async {
    if (_isSyncing) return; // Skip if already syncing
    if (!await isAuthorized) {
      throw Exception('Drive not authorized');
    }

    _isSyncing = true;
    try {
      await _driveService.checkFolderAccess();

      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString('sync_last_timestamp') ?? DateTime(1970).toIso8601String();
      final lastSyncTimestamp = DateTime.parse(lastSync);

      if (forcePull || await _hasPendingPull(lastSyncTimestamp)) {
        await _pullAndMergeDeltas();
      }

      if (await _hasPendingPush()) {
        await _pushPendingDeltas();
      }

      await prefs.setString('sync_last_timestamp', DateTime.now().toIso8601String());
      await prefs.setString('sync_last_result', 'success');
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sync_last_timestamp', DateTime.now().toIso8601String());
      await prefs.setString('sync_last_result', 'failed: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> scheduleSync(int minutes) async {
    if (minutes <= 0) return;
    await Workmanager().registerPeriodicTask(
      'auto-sync-task',
      'auto-sync',
      frequency: Duration(minutes: minutes),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  Future<void> cancelSync() async {
    await Workmanager().cancelAll();
  }

  Future<void> _pullAndMergeDeltas() async {
    final remoteData = await _driveService.pullDeltas();
    final remoteTimestamp = DateTime.parse(remoteData['lastSyncTimestamp']);
    final prefs = await SharedPreferences.getInstance();
    final localTimestamp = DateTime.parse(prefs.getString('sync_last_timestamp') ?? '1970-01-01T00:00:00Z');

    if (remoteTimestamp.isBefore(localTimestamp)) return;

    final deltas = remoteData['deltas'] as List;
    for (final deltaJson in deltas) {
      final delta = _Delta.fromJson(deltaJson);
      if (delta.timestamp.isBefore(localTimestamp)) continue;

      await _applyDelta(delta);
    }

    await prefs.setString('sync_last_timestamp', remoteTimestamp.toIso8601String());
  }

  Future<void> _pushPendingDeltas() async {
    final pendingDeltas = await _dbService.getPendingDeltas();
    if (pendingDeltas.isEmpty) return;

    final remoteData = await _driveService.pullDeltas();
    final remoteDeltas = remoteData['deltas'] as List<dynamic>;

    final allDeltas = [...remoteDeltas];
    final deltaIds = <int>[];

    for (final localDelta in pendingDeltas) {
      final localJson = json.decode(localDelta['entry_json']);
      final localDeltaObj = _Delta(
        type: localDelta['type'],
        tableName: localDelta['table_name'],
        entryJson: localJson,
        timestamp: DateTime.parse(localDelta['timestamp']),
        modifiedBy: localDelta['modified_by'],
      );

      final hasConflict = remoteDeltas.any((remote) {
        final r = _Delta.fromJson(remote);
        return r.type != 'delete' &&
               r.tableName == localDeltaObj.tableName &&
               (r.entryJson['id'] == localDeltaObj.entryJson['id'] ||
                (r.entryJson['startTime'] == localDeltaObj.entryJson['startTime'] &&
                 r.type == 'insert' && localDeltaObj.type == 'insert'));
      });

      if (!hasConflict) {
        allDeltas.add(localDeltaObj.toJson());
        deltaIds.add(localDelta['id'] as int);
      }
    }

    final pushData = {
      'deltas': allDeltas,
      'lastSyncTimestamp': DateTime.now().toUtc().toIso8601String(),
      'version': '1.0.0',
    };

    await _driveService.pushDeltas(pushData);
    await _dbService.markDeltasSynced(deltaIds);
    await _dbService.clearSyncedDeltas();
  }

  Future<void> _applyDelta(_Delta delta) async {
    switch (delta.type) {
      case 'insert':
      case 'update':
        if (delta.tableName == 'sleep_entries') {
          final entry = SleepEntry.fromJson(delta.entryJson);
          final existing = await _dbService.getSleepEntryById(entry.id!);
          if (existing == null || delta.timestamp.isAfter(existing.lastModified)) {
            if (delta.type == 'insert') {
              await _dbService.insertSleepEntry(entry);
            } else {
              await _dbService.updateSleepEntry(entry);
            }
          }
        } else {
          final entry = FeedingEntry.fromJson(delta.entryJson);
          final existing = await _dbService.getFeedingEntryById(entry.id!);
          if (existing == null || delta.timestamp.isAfter(existing.lastModified)) {
            if (delta.type == 'insert') {
              await _dbService.insertFeedingEntry(entry);
            } else {
              await _dbService.updateFeedingEntry(entry);
            }
          }
        }
        break;
      case 'delete':
        final id = delta.entryJson['id'] as int;
        if (delta.tableName == 'sleep_entries') {
          await _dbService.deleteSleepEntry(id);
        } else {
          await _dbService.deleteFeedingEntry(id);
        }
        break;
    }
  }

  Future<bool> _hasPendingPull(DateTime lastSyncTimestamp) async {
    final interval = Duration(minutes: await _getAutoSyncInterval());
    return DateTime.now().subtract(interval).isAfter(lastSyncTimestamp);
  }

  Future<bool> _hasPendingPush() async {
    final deltas = await _dbService.getPendingDeltas();
    return deltas.isNotEmpty;
  }

  Future<int> _getAutoSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('sync_auto_interval') ?? 180;
  }

  Future<void> _triggerBackgroundSync() async {
    if (await isAuthorized && !_isSyncing) {
      try {
        await sync();
      } catch (e) {
        debugPrint('Background sync failed: $e');
      }
    }
  }

  Future<int> logSleepInsert(SleepEntry entry) async {
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    final id = await _dbService.insertSleepEntry(updatedEntry);
    await _triggerBackgroundSync();
    return id;
  }

  Future<void> logSleepUpdate(SleepEntry entry) async {
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    await _dbService.updateSleepEntry(updatedEntry);
    await _triggerBackgroundSync();
  }

  Future<void> logSleepDelete(int id) async {
    await _dbService.deleteSleepEntry(id);
    await _triggerBackgroundSync();
  }

  Future<int> logFeedingInsert(FeedingEntry entry) async {
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    final id = await _dbService.insertFeedingEntry(updatedEntry);
    await _triggerBackgroundSync();
    return id;
  }

  Future<void> logFeedingUpdate(FeedingEntry entry) async {
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    await _dbService.updateFeedingEntry(updatedEntry);
    await _triggerBackgroundSync();
  }

  Future<void> logFeedingDelete(int id) async {
    await _dbService.deleteFeedingEntry(id);
    await _triggerBackgroundSync();
  }
}

class _Delta {
  final String type;
  final String tableName;
  final Map<String, dynamic> entryJson;
  final DateTime timestamp;
  final String modifiedBy;

  _Delta({
    required this.type,
    required this.tableName,
    required this.entryJson,
    required this.timestamp,
    required this.modifiedBy,
  });

  factory _Delta.fromJson(Map<String, dynamic> json) {
    return _Delta(
      type: json['type'],
      tableName: json['table_name'],
      entryJson: json['entry_json'],
      timestamp: DateTime.parse(json['timestamp']),
      modifiedBy: json['modified_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'table_name': tableName,
      'entry_json': entryJson,
      'timestamp': timestamp.toIso8601String(),
      'modified_by': modifiedBy,
    };
  }
}
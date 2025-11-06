import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'drive_service.dart';
import 'database.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';
import 'widget_service.dart';
import '../app_state.dart';

class SyncService {
  final DriveService _driveService = DriveService();
  final DatabaseService _dbService = DatabaseService();
  final AppState? _appState;
  bool _isSyncing = false;

  SyncService({AppState? appState}) : _appState = appState;

  Future<bool> get isAuthorized async {
    return await _driveService.isAuthorized;
  }

  Future<bool> get isDriveAuthorized async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('sync_drive_authorized') ?? false;
  }

  Future<String?> get currentUserEmail async => await _driveService.currentUserEmail;

  Future<void> sync({bool forcePull = false, bool isBackground = false}) async {
    if (_isSyncing) {
      debugPrint('Sync skipped: already in progress');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final authorized = await isAuthorized;
    if (!authorized) {
      debugPrint('Sync skipped: Drive not authorized');
      if (isBackground) return;
      throw Exception('Please authorize Google Drive in Settings');
    }

    _isSyncing = true;
    try {
      await _driveService.checkFolderAccess(isBackground: isBackground);

      final lastSync = prefs.getString('sync_last_timestamp') ?? DateTime(1970).toIso8601String();
      final lastSyncTimestamp = DateTime.parse(lastSync);

      if (forcePull || await _hasPendingPull(lastSyncTimestamp)) {
        await _pullAndMergeDeltas(isBackground: isBackground);
      }

      if (await _hasPendingPush()) {
        await _pushPendingDeltas(isBackground: isBackground);
      }

      await prefs.setString('sync_last_timestamp', DateTime.now().toIso8601String());
      await prefs.setString('sync_last_result', 'success');
      _appState?.notifyDatabaseChanged();
    } catch (e) {
      await prefs.setString('sync_last_timestamp', DateTime.now().toIso8601String());
      await prefs.setString('sync_last_result', 'failed: $e');
      debugPrint('Sync failed: $e');
      if (!isBackground) rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pullAndMergeDeltas({bool isBackground = false}) async {
    final remoteData = await _driveService.pullDeltas(isBackground: isBackground);
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
    _appState?.notifyDatabaseChanged();
  }

  Future<void> _pushPendingDeltas({bool isBackground = false}) async {
    final pendingDeltas = await _dbService.getPendingDeltas();
    if (pendingDeltas.isEmpty) return;

    final remoteData = await _driveService.pullDeltas(isBackground: isBackground);
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

    await _driveService.pushDeltas(pushData, isBackground: isBackground);
    await _dbService.markDeltasSynced(deltaIds);
    await _dbService.clearSyncedDeltas();
    _appState?.notifyDatabaseChanged();
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
    return DateTime.now().subtract(const Duration(minutes: 180)).isAfter(lastSyncTimestamp);
  }

  Future<bool> _hasPendingPush() async {
    final deltas = await _dbService.getPendingDeltas();
    return deltas.isNotEmpty;
  }

  Future<int> logSleepInsert(SleepEntry entry) async {
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    final id = await _dbService.insertSleepEntry(updatedEntry);
    if (await isAuthorized) {
      try {
        await sync();
      } catch (e) {
        debugPrint('Sync after sleep insert failed: $e');
      }
    }
    _appState?.notifyDatabaseChanged();
    return id;
  }

  Future<void> logSleepUpdate(SleepEntry entry) async {
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    await _dbService.updateSleepEntry(updatedEntry);
    if (await isAuthorized) {
      try {
        await sync();
      } catch (e

) {
        debugPrint('Sync after sleep update failed: $e');
      }
    }
    _appState?.notifyDatabaseChanged();
  }

  Future<void> logSleepDelete(int id) async {
    await _dbService.deleteSleepEntry(id);
    if (await isAuthorized) {
      try {
        await sync();
      } catch (e) {
        debugPrint('Sync after sleep delete failed: $e');
      }
    }
    _appState?.notifyDatabaseChanged();
  }

  Future<int> logFeedingInsert(FeedingEntry entry) async {
    debugPrint("logFeedingInsert");
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    final id = await _dbService.insertFeedingEntry(updatedEntry);
    if (await isAuthorized) {
      try {
        await sync();
        await WidgetService.syncAppToWidget(triggerUpdate: false, appState: _appState);
      } catch (e) {
        debugPrint('Sync after feeding insert failed: $e');
      }
    }
    _appState?.notifyDatabaseChanged();
    return id;
  }

  Future<void> logFeedingUpdate(FeedingEntry entry) async {
    debugPrint("logFeedingUpdate");
    final userEmail = await currentUserEmail ?? 'local';
    final updatedEntry = entry.copyWith(
      lastModified: entry.lastModified ?? DateTime.now(),
      modifiedBy: userEmail,
    );
    await _dbService.updateFeedingEntry(updatedEntry);
    if (await isAuthorized) {
      try {
        await sync();
        await WidgetService.syncAppToWidget(triggerUpdate: false, appState: _appState);
      } catch (e) {
        debugPrint('Sync after feeding update failed: $e');
      }
    }
    _appState?.notifyDatabaseChanged();
  }

  Future<void> logFeedingDelete(int id) async {
    debugPrint("logFeedingDelete");
    await _dbService.deleteFeedingEntry(id);
    if (await isAuthorized) {
      try {
        await sync();
        await WidgetService.syncAppToWidget(triggerUpdate: false, appState: _appState);
      } catch (e) {
        debugPrint('Sync after feeding delete failed: $e');
      }
    }
    _appState?.notifyDatabaseChanged();
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
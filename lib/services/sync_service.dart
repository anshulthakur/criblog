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

  Future<String?> get currentUserEmail async {
    return await _driveService.currentUserEmail ?? 'local';
  }

  Future<void> sync({bool forcePull = false, bool isBackground = false, int retryCount = 3}) async {
    if (_isSyncing) {
      debugPrint('Sync skipped: already in progress');
      return;
    }

    _isSyncing = true;
    final prefs = await SharedPreferences.getInstance();
    int attempts = 0;
    while (attempts < retryCount) {
      try {
        final lastSyncId = prefs.getString('last_sync_id') ?? '0';
        final syncResult = await _driveService.checkSync(lastSyncId);
        debugPrint('SyncService: Check sync result: ${syncResult['status']}');

        if (syncResult['status'] == 'sync_ok') {
          debugPrint('SyncService: Everything in sync');
          await prefs.setString('last_sync_id', syncResult['lastSyncId']);
          await prefs.setString('sync_last_result', 'success');
          if (!isBackground) {
            _appState?.notifyDatabaseChanged();
            debugPrint('Sync: Notified AppState');
          }
          return;
        }

        if (syncResult['status'] == 'updates_needed' || forcePull) {
          await _pullAndMergeDeltas(syncResult, isBackground: isBackground);
        }

        if (await _hasPendingPush()) {
          await _pushPendingDeltas(syncResult['lastSyncId'], isBackground: isBackground);
        } else {
          await prefs.setString('last_sync_id', syncResult['lastSyncId']);
          await prefs.setString('sync_last_result', 'success');
        }

        if (!isBackground) {
          _appState?.notifyDatabaseChanged();
          debugPrint('Sync: Notified AppState');
        }
        return;
      } catch (e) {
        attempts++;
        debugPrint('Sync attempt $attempts failed: $e');
        if (attempts >= retryCount) {
          await prefs.setString('sync_last_result', 'failed: $e');
          debugPrint('Sync failed after $retryCount attempts: $e');
          if (!isBackground) rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempts));
      } finally {
        _isSyncing = false;
      }
    }
  }

  Future<void> _pullAndMergeDeltas(Map<String, dynamic> syncResult, {bool isBackground = false}) async {
    final deltas = syncResult['deltas'] as List;
    final prefs = await SharedPreferences.getInstance();
    final localSyncId = int.parse(prefs.getString('last_sync_id') ?? '0');

    for (final deltaJson in deltas) {
      final delta = Delta.fromJson(deltaJson);
      final deltaTimestamp = int.parse(delta.timestamp);

      if (deltaTimestamp <= localSyncId) {
        debugPrint('Skipped delta: timestamp=${delta.timestamp} <= localSyncId=$localSyncId');
        continue;
      }

      await _applyDelta(delta);
    }

    await prefs.setString('last_sync_id', syncResult['lastSyncId']);
    if (!isBackground) {
      _appState?.notifyDatabaseChanged();
      debugPrint('PullAndMergeDeltas: Notified AppState');
    }
  }

  Future<void> _pushPendingDeltas(String serverLastSyncId, {bool isBackground = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingDeltas = await _dbService.getPendingDeltas();
    if (pendingDeltas.isEmpty) {
      debugPrint('No pending deltas to push');
      await prefs.setString('last_sync_id', serverLastSyncId);
      await prefs.setString('sync_last_result', 'success');
      return;
    }

    final deltaIds = <int>[];
    final deltasToPush = pendingDeltas.map((delta) => {
      'timestamp': delta['timestamp'],
      'operation': delta['operation'],
      'table': delta['table'],
      'data': delta['data'],
    }).toList();

    final pushResult = await _driveService.pushDeltas(deltasToPush, serverLastSyncId);
    deltaIds.addAll(pendingDeltas.map((delta) => delta['id'] as int));
    await _dbService.markDeltasSynced(deltaIds);
    await _dbService.clearSyncedDeltas();

    if (pushResult['lastSyncId'] != null) {
      await prefs.setString('last_sync_id', pushResult['lastSyncId']);
      debugPrint('SyncService: Updated last_sync_id to ${pushResult['lastSyncId']} from push_deltas');
    } else {
      debugPrint('SyncService: No lastSyncId in push_deltas response, using serverLastSyncId=$serverLastSyncId');
      await prefs.setString('last_sync_id', serverLastSyncId);
    }
    await prefs.setString('sync_last_result', 'success');

    if (!isBackground) {
      _appState?.notifyDatabaseChanged();
      debugPrint('PushPendingDeltas: Notified AppState');
    }
  }

  Future<void> _applyDelta(Delta delta) async {
    final tableName = delta.table == 'feeding' ? 'feeding_entries' : 'sleep_entries';
    final id = int.parse(delta.data['id']);
    final deltaTimestamp = int.parse(delta.timestamp);

    if (delta.operation == 'insert' || delta.operation == 'update') {
      final entryJson = _dbService.deltaDataToEntry(delta.data, tableName);
      if (tableName == 'sleep_entries') {
        final existing = await _dbService.getSleepEntryById(id);
        final existingTimestamp = existing != null ? existing.lastModified.millisecondsSinceEpoch : 0;
        if (existing == null || deltaTimestamp >= existingTimestamp) {
          final entry = SleepEntry.fromJson(entryJson);
          if (delta.operation == 'insert') {
            await _dbService.insertSleepEntry(entry);
            debugPrint('Applied delta: Inserted sleep entry id=$id');
          } else {
            await _dbService.updateSleepEntry(entry);
            debugPrint('Applied delta: Updated sleep entry id=$id');
          }
        } else {
          debugPrint('Skipped delta: Existing sleep entry id=$id, lastModified=$existingTimestamp >= delta.timestamp=$deltaTimestamp');
        }
      } else {
        final existing = await _dbService.getFeedingEntryById(id);
        final existingTimestamp = existing != null ? existing.lastModified.millisecondsSinceEpoch : 0;
        if (existing == null || deltaTimestamp >= existingTimestamp) {
          final entry = FeedingEntry.fromJson(entryJson);
          if (delta.operation == 'insert') {
            await _dbService.insertFeedingEntry(entry);
            debugPrint('Applied delta: Inserted feeding entry id=$id');
          } else {
            await _dbService.updateFeedingEntry(entry);
            debugPrint('Applied delta: Updated feeding entry id=$id');
          }
        } else {
          debugPrint('Skipped delta: Existing feeding entry id=$id, lastModified=$existingTimestamp >= delta.timestamp=$deltaTimestamp');
        }
      }
    } else if (delta.operation == 'delete') {
      if (tableName == 'sleep_entries') {
        await _dbService.deleteSleepEntry(id);
        debugPrint('Applied delta: Deleted sleep entry id=$id');
      } else {
        await _dbService.deleteFeedingEntry(id);
        debugPrint('Applied delta: Deleted feeding entry id=$id');
      }
    }
  }

  Future<bool> _hasPendingPush() async {
    final deltas = await _dbService.getPendingDeltas();
    debugPrint('Pending deltas count: ${deltas.length}');
    return deltas.isNotEmpty;
  }

  Future<int> logSleepInsert(SleepEntry entry) async {
    final userEmail = await currentUserEmail;
    final updatedEntry = entry.copyWith(
      lastModified: DateTime.now().toUtc(),
      modifiedBy: userEmail,
    );
    final id = await _dbService.insertSleepEntry(updatedEntry);
    debugPrint('logSleepInsert: Inserted sleep entry id=$id');
    try {
      await sync();
    } catch (e) {
      debugPrint('Sync after sleep insert failed: $e');
    }
    _appState?.notifyDatabaseChanged();
    debugPrint('logSleepInsert: Notified AppState');
    return id;
  }

  Future<void> logSleepUpdate(SleepEntry entry) async {
    final userEmail = await currentUserEmail;
    final updatedEntry = entry.copyWith(
      lastModified: DateTime.now().toUtc(),
      modifiedBy: userEmail,
    );
    await _dbService.updateSleepEntry(updatedEntry);
    debugPrint('logSleepUpdate: Updated sleep entry $updatedEntry');
    try {
      await sync();
    } catch (e) {
      debugPrint('Sync after sleep update failed: $e');
    }
    _appState?.notifyDatabaseChanged();
    debugPrint('logSleepUpdate: Notified AppState');
  }

  Future<void> logSleepDelete(int id) async {
    await _dbService.deleteSleepEntry(id);
    debugPrint('logSleepDelete: Deleted sleep entry id=$id');
    try {
      await sync();
    } catch (e) {
      debugPrint('Sync after sleep delete failed: $e');
    }
    _appState?.notifyDatabaseChanged();
    debugPrint('logSleepDelete: Notified AppState');
  }

  Future<int> logFeedingInsert(FeedingEntry entry) async {
    debugPrint("logFeedingInsert");
    final userEmail = await currentUserEmail;
    final updatedEntry = entry.copyWith(
      lastModified: DateTime.now().toUtc(),
      modifiedBy: userEmail,
    );
    final id = await _dbService.insertFeedingEntry(updatedEntry);
    debugPrint('logFeedingInsert: Inserted feeding entry id=$id');
    try {
      await sync();
      await WidgetService.syncAppToWidget(triggerUpdate: true, appState: _appState);
    } catch (e) {
      debugPrint('Sync after feeding insert failed: $e');
    }
    _appState?.notifyDatabaseChanged();
    debugPrint('logFeedingInsert: Notified AppState');
    return id;
  }

  Future<void> logFeedingUpdate(FeedingEntry entry) async {
    debugPrint("logFeedingUpdate");
    final userEmail = await currentUserEmail;
    final updatedEntry = entry.copyWith(
      lastModified: DateTime.now().toUtc(),
      modifiedBy: userEmail,
    );
    await _dbService.updateFeedingEntry(updatedEntry);
    debugPrint('logFeedingUpdate: Updated feeding entry $updatedEntry');
    try {
      await sync();
      await WidgetService.syncAppToWidget(triggerUpdate: true, appState: _appState);
    } catch (e) {
      debugPrint('Sync after feeding update failed: $e');
    }
    _appState?.notifyDatabaseChanged();
    debugPrint('logFeedingUpdate: Notified AppState');
  }

  Future<void> logFeedingDelete(int id) async {
    debugPrint("logFeedingDelete");
    await _dbService.deleteFeedingEntry(id);
    debugPrint('logFeedingDelete: Deleted feeding entry id=$id');
    try {
      await sync();
      await WidgetService.syncAppToWidget(triggerUpdate: true, appState: _appState);
    } catch (e) {
      debugPrint('Sync after feeding delete failed: $e');
    }
    _appState?.notifyDatabaseChanged();
    debugPrint('logFeedingDelete: Notified AppState');
  }
}

class Delta {
  final String timestamp;
  final String operation;
  final String table;
  final Map<String, dynamic> data;
  final String modifiedBy;

  Delta({
    required this.timestamp,
    required this.operation,
    required this.table,
    required this.data,
    required this.modifiedBy,
  });

  factory Delta.fromJson(Map<String, dynamic> json) {
    return Delta(
      timestamp: json['timestamp'],
      operation: json['operation'],
      table: json['table'],
      data: json['data'],
      modifiedBy: json['modified_by'] ?? 'remote',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'operation': operation,
      'table': table,
      'data': data,
      'modified_by': modifiedBy,
    };
  }
}
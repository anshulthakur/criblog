import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database.dart';
import '../services/sync_service.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';
import '../app_state.dart';

mixin EntryController<T extends StatefulWidget> on State<T> {
  bool _isSleepOngoing = false;
  bool _isFeedingOngoing = false;
  SleepEntry? _lastSleep;
  FeedingEntry? _lastFeeding;
  FeedingSource _selectedSource = FeedingSource.breast;
  final _syncService = SyncService();
  final _dbService = DatabaseService();

  bool get isSleepOngoing => _isSleepOngoing;
  bool get isFeedingOngoing => _isFeedingOngoing;
  FeedingSource get selectedSource => _selectedSource;
  SleepEntry? get lastSleep => _lastSleep;
  FeedingEntry? get lastFeeding => _lastFeeding;

  @mustCallSuper
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().addListener(_onAppStateChanged);
      _refreshStatus();
    });
  }

  @mustCallSuper
  @override
  void dispose() {
    context.read<AppState>().removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    debugPrint('EntryController: AppState changed, refreshing status');
    _refreshStatus();
  }

  Future<void> initEntryState() async => _refreshStatus();

  Future<void> refreshEntryState() async => _refreshStatus();

  Future<void> _refreshStatus() async {
    debugPrint('EntryController: Refreshing status');
    final ongoingSleep = await _dbService.getOngoingSleep();
    final ongoingFeeding = await _dbService.getOngoingFeeding();

    setState(() {
      _isSleepOngoing = ongoingSleep != null;
      _lastSleep = ongoingSleep;
      _isFeedingOngoing = ongoingFeeding != null;
      _lastFeeding = ongoingFeeding;
      _selectedSource = ongoingFeeding?.source ?? FeedingSource.breast;
      debugPrint(
          'EntryController: Updated state - sleep: $_isSleepOngoing, feeding: $_isFeedingOngoing, source: $_selectedSource');
    });
  }

  Future<void> toggleSleep() async {
    final now = DateTime.now();
    if (_isSleepOngoing) {
      final updated = SleepEntry(
        id: _lastSleep!.id,
        startTime: _lastSleep!.startTime,
        endTime: now,
        lastModified: now,
        modifiedBy: await _syncService.currentUserEmail ?? 'local',
      );
      try {
        await _syncService.logSleepUpdate(updated);
        _snack('Sleep ended at ${_fmt(now)}');
      } catch (e) {
        _snack('Sleep ended, but sync failed: $e');
      }
      setState(() => _isSleepOngoing = false);
    } else {
      final newEntry = SleepEntry(
        startTime: now,
        lastModified: now,
        modifiedBy: await _syncService.currentUserEmail ?? 'local',
      );
      try {
        final insertedId = await _syncService.logSleepInsert(newEntry);
        final entryWithId = newEntry.copyWith(id: insertedId);
        _snack('Sleep started at ${_fmt(now)}');
        setState(() {
          _isSleepOngoing = true;
          _lastSleep = entryWithId;
        });
      } catch (e) {
        _snack('Sleep started, but sync failed: $e');
      }
    }
    await _refreshStatus();
  }

  Future<void> toggleFeeding() async {
    final now = DateTime.now();
    if (_isFeedingOngoing) {
      final updated = FeedingEntry(
        id: _lastFeeding!.id,
        startTime: _lastFeeding!.startTime,
        endTime: now,
        source: _lastFeeding!.source,
        lastModified: now,
        modifiedBy: await _syncService.currentUserEmail ?? 'local',
      );
      try {
        await _syncService.logFeedingUpdate(updated);
        _snack('Feeding ended at ${_fmt(now)}');
      } catch (e) {
        _snack('Feeding ended, but sync failed: $e');
      }
    } else {
      final newEntry = FeedingEntry(
        startTime: now,
        endTime: null,
        source: _selectedSource,
        lastModified: now,
        modifiedBy: await _syncService.currentUserEmail ?? 'local',
      );
      try {
        final insertedId = await _syncService.logFeedingInsert(newEntry);
        final entryWithId = newEntry.copyWith(id: insertedId);
        _snack('Feeding (${_srcLabel(_selectedSource)}) started at ${_fmt(now)}');
        setState(() {
          _isFeedingOngoing = true;
          _lastFeeding = entryWithId;
        });
      } catch (e) {
        _snack('Feeding started, but sync failed: $e');
      }
    }
    await _refreshStatus();
  }

  void setFeedingSource(FeedingSource source) => setState(() {
        _selectedSource = source;
        debugPrint('EntryController: Set feeding source to $source');
      });

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime d) => d.toString().substring(11, 16);
  String _srcLabel(FeedingSource s) => s == FeedingSource.breast ? 'Breast' : 'Expressed';
}
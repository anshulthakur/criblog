import 'package:flutter/material.dart';
import '../services/database.dart';
import '../services/sync_service.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';
import '../app_state.dart';

class EntryController extends ChangeNotifier {
  bool _isSleepOngoing = false;
  bool _isFeedingOngoing = false;
  SleepEntry? _lastSleep;
  FeedingEntry? _lastFeeding;
  FeedingSource _selectedSource = FeedingSource.breast;
  final _syncService = SyncService();
  final _dbService = DatabaseService();
  late AppState _appState;

  bool get isSleepOngoing => _isSleepOngoing;
  bool get isFeedingOngoing => _isFeedingOngoing;
  FeedingSource get selectedSource => _selectedSource;
  SleepEntry? get lastSleep => _lastSleep;
  FeedingEntry? get lastFeeding => _lastFeeding;

  EntryController(AppState appState) {
    debugPrint('EntryController: Initialized');
    _appState = appState;
    _appState.addListener(_onAppStateChanged);
    _refreshStatus();
  }

  @override
  void dispose() {
    debugPrint('EntryController: dispose');
    _appState.removeListener(_onAppStateChanged);
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

    _isSleepOngoing = ongoingSleep != null;
    _lastSleep = ongoingSleep;
    _isFeedingOngoing = ongoingFeeding != null;
    _lastFeeding = ongoingFeeding;
    _selectedSource = ongoingFeeding?.source ?? FeedingSource.breast;
    debugPrint(
        'EntryController: Updated state - sleep: $_isSleepOngoing, feeding: $_isFeedingOngoing, source: $_selectedSource');
    notifyListeners();
  }

  Future<void> toggleSleep(BuildContext context) async {
    final now = DateTime.now();
    if (_isSleepOngoing) {
      final updated = SleepEntry(
        id: _lastSleep!.id,
        startTime: _lastSleep!.startTime,
        endTime: now,
        lastModified: now,
        modifiedBy: await _syncService.currentUserEmail ?? 'local',
      );
      await _syncService.logSleepUpdate(updated);
      _snack(context, 'Sleep ended at ${_fmt(now)}');
      _isSleepOngoing = false;
    } else {
      final newEntry = SleepEntry(
        startTime: now,
        lastModified: now,
        modifiedBy: await _syncService.currentUserEmail ?? 'local',
      );
      final insertedId = await _syncService.logSleepInsert(newEntry);
      final entryWithId = newEntry.copyWith(id: insertedId);
      _snack(context, 'Sleep started at ${_fmt(now)}');
      _isSleepOngoing = true;
      _lastSleep = entryWithId;
    }
    await _refreshStatus();
  }

  Future<void> toggleFeeding(BuildContext context) async {
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
      await _syncService.logFeedingUpdate(updated);
      _snack(context, 'Feeding ended at ${_fmt(now)}');
    } else {
      final newEntry = FeedingEntry(
        startTime: now,
        endTime: null,
        source: _selectedSource,
        lastModified: now,
        modifiedBy: await _syncService.currentUserEmail ?? 'local',
      );
      final insertedId = await _syncService.logFeedingInsert(newEntry);
      final entryWithId = newEntry.copyWith(id: insertedId);
      _snack(context, 'Feeding (${_srcLabel(_selectedSource)}) started at ${_fmt(now)}');
      _isFeedingOngoing = true;
      _lastFeeding = entryWithId;
    }
    await _refreshStatus();
  }

  void setFeedingSource(FeedingSource source) {
    _selectedSource = source;
    debugPrint('EntryController: Set feeding source to $source');
    notifyListeners();
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime d) => d.toString().substring(11, 16);
  String _srcLabel(FeedingSource s) => s == FeedingSource.breast ? 'Breast' : 'Expressed';
}
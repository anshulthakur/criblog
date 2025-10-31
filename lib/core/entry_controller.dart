// lib/core/entry_controller.dart
import 'package:flutter/material.dart';
import '../services/database.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';

/// Mix-in that can be added to any State\<T\> where T extends StatefulWidget.
/// It contains **all** the logic for starting / ending sleep & feeding.
mixin EntryController<T extends StatefulWidget> on State<T> {
  // ------------------------------------------------------------------ state
  bool _isSleepOngoing = false;
  bool _isFeedingOngoing = false;
  SleepEntry? _lastSleep;
  FeedingEntry? _lastFeeding;
  FeedingSource _selectedSource = FeedingSource.breast;

  // ------------------------------------------------------------------ getters
  bool get isSleepOngoing => _isSleepOngoing;
  bool get isFeedingOngoing => _isFeedingOngoing;
  FeedingSource get selectedSource => _selectedSource;
  SleepEntry? get lastSleep => _lastSleep;
  FeedingEntry? get lastFeeding => _lastFeeding;

  // ------------------------------------------------------------------ init
  @mustCallSuper
  Future<void> initEntryState() async => _refreshStatus();

  // ------------------------------------------------------------------ refresh
  Future<void> refreshEntryState() async => _refreshStatus();

  Future<void> _refreshStatus() async {
    final ongoingSleep = await DatabaseService().getOngoingSleep();
    final ongoingFeeding = await DatabaseService().getOngoingFeeding();

    setState(() {
      _isSleepOngoing = ongoingSleep != null;
      _lastSleep = ongoingSleep;

      _isFeedingOngoing = ongoingFeeding != null;
      _lastFeeding = ongoingFeeding;
      _selectedSource = ongoingFeeding?.source ?? FeedingSource.breast;
    });
  }

  // ------------------------------------------------------------------ sleep
  Future<void> toggleSleep() async {
    final now = DateTime.now();
    if (_isSleepOngoing) {
      final updated = SleepEntry(
        id: _lastSleep!.id,
        startTime: _lastSleep!.startTime,
        endTime: now,
      );
      await DatabaseService().updateSleepEntry(updated);
      _snack('Sleep ended at ${_fmt(now)}');
      setState(() => _isSleepOngoing = false);
    } else {
      final newEntry = SleepEntry(startTime: now);
      final insertedId = await DatabaseService().insertSleepEntry(newEntry);
      final entryWithId = newEntry.copyWith(id: insertedId);
      _snack('Sleep started at ${_fmt(now)}');
      setState(() {
        _isSleepOngoing = true;
        _lastSleep = entryWithId;
      });
    }
  }

  // ------------------------------------------------------------------ feeding
  Future<void> toggleFeeding() async {
    final now = DateTime.now();
    if (_isFeedingOngoing) {
      // END: preserve id
      final updated = FeedingEntry(
        id: _lastFeeding!.id,
        startTime: _lastFeeding!.startTime,
        endTime: now,
        source: _lastFeeding!.source,
      );
      await DatabaseService().updateFeedingEntry(updated);
      _snack('Feeding ended at ${_fmt(now)}');
    } else {
      // START: insert + get id
      final newEntry = FeedingEntry(
        startTime: now,
        endTime: null,
        source: _selectedSource,
      );
      final insertedId = await DatabaseService().insertFeedingEntry(newEntry);
      final entryWithId = newEntry.copyWith(id: insertedId); // use copyWith
      _snack('Feeding (${_srcLabel(_selectedSource)}) started at ${_fmt(now)}');
      setState(() {
        _isFeedingOngoing = true;
        _lastFeeding = entryWithId;
      });
    }
    // Optional: refresh from DB to be 100% safe
    await _refreshStatus();
  }

  // ------------------------------------------------------------------ source
  void setFeedingSource(FeedingSource source) => setState(() => _selectedSource = source);

  // ------------------------------------------------------------------ helpers
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime d) => d.toString().substring(11, 16); // HH:MM
  String _srcLabel(FeedingSource s) => s == FeedingSource.breast ? 'Breast' : 'Expressed';
}
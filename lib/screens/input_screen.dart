import 'package:flutter/material.dart';
import '../services/database.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  bool _isSleepOngoing = false;
  bool _isFeedingOngoing = false;
  SleepEntry? _lastSleepEntry;
  FeedingEntry? _lastFeedingEntry;
  FeedingSource _selectedSource = FeedingSource.breast;

  @override
  void initState() {
    super.initState();
    _checkStatuses();
  }

  Future<void> _checkStatuses() async {
    final ongoingSleep = await DatabaseService().getOngoingSleep();
    final ongoingFeeding = await DatabaseService().getOngoingFeeding();

    setState(() {
      _isSleepOngoing = ongoingSleep != null;
      _lastSleepEntry = ongoingSleep;

      _isFeedingOngoing = ongoingFeeding != null;
      _lastFeedingEntry = ongoingFeeding;
      _selectedSource = ongoingFeeding?.source ?? FeedingSource.breast;
    });
  }

  Future<void> _toggleSleep() async {
    final now = DateTime.now();
    if (_isSleepOngoing) {
      final updated = SleepEntry(
        id: _lastSleepEntry!.id,
        startTime: _lastSleepEntry!.startTime,
        endTime: now,
      );
      await DatabaseService().updateSleepEntry(updated);
      _showSnackBar('Sleep ended at ${_formatTime(now)}');
      setState(() {
        _isSleepOngoing = false;
      });
    } else {
      final newEntry = SleepEntry(startTime: now);
      await DatabaseService().insertSleepEntry(newEntry);
      _showSnackBar('Sleep started at ${_formatTime(now)}');
      setState(() {
        _isSleepOngoing = true;
        _lastSleepEntry = newEntry;
      });
    }
  }

  Future<void> _toggleFeeding() async {
    final now = DateTime.now();
    if (_isFeedingOngoing) {
      final updated = FeedingEntry(
        id: _lastFeedingEntry!.id,
        startTime: _lastFeedingEntry!.startTime,
        endTime: now,
        source: _lastFeedingEntry!.source,
      );
      await DatabaseService().updateFeedingEntry(updated);
      _showSnackBar('Feeding ended at ${_formatTime(now)}');
      setState(() {
        _isFeedingOngoing = false;
      });
    } else {
      final newEntry = FeedingEntry(
        startTime: now,
        endTime: null,
        source: _selectedSource,
      );
      await DatabaseService().insertFeedingEntry(newEntry);
      _showSnackBar('Feeding started (${_sourceLabel(_selectedSource)}) at ${_formatTime(now)}');
      setState(() {
        _isFeedingOngoing = true;
        _lastFeedingEntry = newEntry;
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _formatTime(DateTime dt) => dt.toString().substring(11, 16);
  String _sourceLabel(FeedingSource source) =>
      source == FeedingSource.breast ? 'Breast' : 'Expressed';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Activity')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // === Feeding Section ===
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Feeding', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SegmentedButton<FeedingSource>(
                      segments: const [
                        ButtonSegment(value: FeedingSource.breast, label: Text('Breast')),
                        ButtonSegment(value: FeedingSource.expressed, label: Text('Expressed')),
                      ],
                      selected: {_selectedSource},
                      onSelectionChanged: (Set<FeedingSource> newSelection) {
                        setState(() {
                          _selectedSource = newSelection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _toggleFeeding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFeedingOngoing ? Colors.red : Colors.orange,
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: Text(
                        _isFeedingOngoing ? 'End Feeding' : 'Start Feeding',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // === Sleep Section ===
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Sleep', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _toggleSleep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSleepOngoing ? Colors.red : Colors.green,
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: Text(
                        _isSleepOngoing ? 'End Sleep' : 'Start Sleep',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // === Status Card ===
            if (_isSleepOngoing || _isFeedingOngoing)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      if (_isSleepOngoing)
                        Text('Sleeping since ${_formatTime(_lastSleepEntry!.startTime)}'),
                      if (_isFeedingOngoing)
                        Text(
                          'Feeding (${_sourceLabel(_lastFeedingEntry!.source)}) '
                          'since ${_formatTime(_lastFeedingEntry!.startTime)}',
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
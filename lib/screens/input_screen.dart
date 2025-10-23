import 'package:flutter/material.dart';
import '../services/database.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  _InputScreenState createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  bool _isSleepOngoing = false;
  SleepEntry? _lastSleepEntry;

  @override
  void initState() {
    super.initState();
    _checkSleepStatus();
  }

  Future<void> _checkSleepStatus() async {
    final entries = await DatabaseService().getSleepEntries();
    setState(() {
      _lastSleepEntry = entries.isNotEmpty ? entries.last : null;
      _isSleepOngoing = _lastSleepEntry != null && _lastSleepEntry!.endTime == null;
    });
  }

  Future<void> _logFeeding() async {
    final now = DateTime.now();
    await DatabaseService().insertFeedingEntry(FeedingEntry(time: now));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Feeding logged at ${now.toString().substring(0, 16)}')),
      );
    }
  }

  Future<void> _toggleSleep() async {
    final now = DateTime.now();
    if (_isSleepOngoing) {
      // End sleep
      final updatedEntry = SleepEntry(
        id: _lastSleepEntry!.id,
        startTime: _lastSleepEntry!.startTime,
        endTime: now,
      );
      await DatabaseService().updateSleepEntry(updatedEntry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sleep ended at ${now.toString().substring(0, 16)}')),
        );
      }
      setState(() {
        _isSleepOngoing = false;
        _lastSleepEntry = updatedEntry;
      });
    } else {
      // Start sleep
      final newEntry = SleepEntry(startTime: now);
      await DatabaseService().insertSleepEntry(newEntry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sleep started at ${now.toString().substring(0, 16)}')),
        );
      }
      setState(() {
        _isSleepOngoing = true;
        _lastSleepEntry = newEntry;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Activity'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _logFeeding,
                child: const Text('Log Feeding'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _toggleSleep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSleepOngoing ? Colors.red : Colors.green,
                ),
                child: Text(_isSleepOngoing ? 'End Sleep' : 'Start Sleep'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
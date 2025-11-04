import 'package:flutter/material.dart';
import '../core/entry_controller.dart';
import '../models/feeding_entry.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> with EntryController<InputScreen> {
  @override
  void initState() {
    super.initState();
    initEntryState();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ---- Feeding Card (WITH selector) ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Feeding',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SegmentedButton<FeedingSource>(
                    segments: const [
                      ButtonSegment(value: FeedingSource.breast, label: Text('Breast')),
                      ButtonSegment(value: FeedingSource.expressed, label: Text('Expressed')),
                    ],
                    selected: {selectedSource},
                    onSelectionChanged: (s) => setFeedingSource(s.first),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFeedingOngoing ? Colors.red : Colors.orange,
                      minimumSize: const Size(double.infinity, 56),
                    ),
                    onPressed: toggleFeeding,
                    child: Text(
                      isFeedingOngoing ? 'End Feeding' : 'Start Feeding',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Sleep Card (unchanged) ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Sleep',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSleepOngoing ? Colors.red : Colors.green,
                      minimumSize: const Size(double.infinity, 56),
                    ),
                    onPressed: toggleSleep,
                    child: Text(
                      isSleepOngoing ? 'End Sleep' : 'Start Sleep',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
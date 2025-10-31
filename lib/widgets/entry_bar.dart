// lib/widgets/entry_bar.dart
import 'package:flutter/material.dart';
import '../core/entry_controller.dart';
import '../models/feeding_entry.dart';

class EntryBar extends StatefulWidget {
  const EntryBar({super.key});

  @override
  State<EntryBar> createState() => _EntryBarState();
}

class _EntryBarState extends State<EntryBar> with EntryController<EntryBar> {
  @override
  void initState() {
    super.initState();
    initEntryState();               // loads ongoing status
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // ---- Feeding (no selector) ----
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isFeedingOngoing ? Colors.red : Colors.orange,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () {
                // Force Breast when using the floating bar
                if (!isFeedingOngoing) setFeedingSource(FeedingSource.breast);
                toggleFeeding();
              },
              child: Text(
                isFeedingOngoing ? 'End Feeding' : 'Start Feeding',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // ---- Sleep ----
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSleepOngoing ? Colors.red : Colors.green,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: toggleSleep,
              child: Text(
                isSleepOngoing ? 'End Sleep' : 'Start Sleep',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
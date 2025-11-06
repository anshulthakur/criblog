import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/entry_controller.dart';
import '../models/feeding_entry.dart';

class EntryBar extends StatelessWidget {
  const EntryBar({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('EntryBar: Building');
    return Consumer<EntryController>(
      builder: (context, controller, child) {
        debugPrint('EntryBar: Consumer rebuilt, isFeedingOngoing: ${controller.isFeedingOngoing}, isSleepOngoing: ${controller.isSleepOngoing}');
        return Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: controller.isFeedingOngoing ? Colors.red : Colors.orange,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () {
                    if (!controller.isFeedingOngoing) controller.setFeedingSource(FeedingSource.breast);
                    controller.toggleFeeding(context);
                  },
                  child: Text(
                    controller.isFeedingOngoing ? 'End Feeding' : 'Start Feeding',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: controller.isSleepOngoing ? Colors.red : Colors.green,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () => controller.toggleSleep(context),
                  child: Text(
                    controller.isSleepOngoing ? 'End Sleep' : 'Start Sleep',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
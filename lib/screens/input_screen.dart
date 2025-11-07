import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/entry_controller.dart';
import '../models/feeding_entry.dart';
import '../app_state.dart';

class InputScreen extends StatelessWidget {
  const InputScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('InputScreen: Building');

    return ChangeNotifierProvider<EntryController>(
      create: (_) => EntryController(Provider.of<AppState>(context, listen: false)),
      child: Consumer<EntryController>(
        builder: (context, controller, child) {
          debugPrint(
              'InputScreen: Consumer rebuilt, isFeedingOngoing: ${controller.isFeedingOngoing}, isSleepOngoing: ${controller.isSleepOngoing}');
          return RefreshIndicator(
            onRefresh: () async {
              debugPrint('InputScreen: Pull-to-refresh triggered');
              await controller.refreshEntryState();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ---- Feeding Card ----
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Text(
                              'Feeding',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<FeedingSource>(
                              segments: const [
                                ButtonSegment(value: FeedingSource.breast, label: Text('Breast')),
                                ButtonSegment(value: FeedingSource.expressed, label: Text('Expressed')),
                              ],
                              selected: {controller.selectedSource},
                              onSelectionChanged: (s) => controller.setFeedingSource(s.first),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: controller.isFeedingOngoing ? Colors.red : Colors.orange,
                                minimumSize: const Size(double.infinity, 56),
                              ),
                              onPressed: () => controller.toggleFeeding(context),
                              child: Text(
                                controller.isFeedingOngoing ? 'End Feeding' : 'Start Feeding',
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ---- Sleep Card ----
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Text(
                              'Sleep',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: controller.isSleepOngoing ? Colors.red : Colors.green,
                                minimumSize: const Size(double.infinity, 56),
                              ),
                              onPressed: () => controller.toggleSleep(context),
                              child: Text(
                                controller.isSleepOngoing ? 'End Sleep' : 'Start Sleep',
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// lib/services/widget_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:home_widget/home_widget.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';
import 'database.dart';

class WidgetService {
  // Keys used by both widget (Kotlin) and app (Dart)
  static const String _keyOngoingSleep = 'widget_ongoing_sleep';
  static const String _keyOngoingFeeding = 'widget_ongoing_feeding';

  // Called from WorkManager when widget button is tapped
  static Future<void> handleFeedingFromWidget() async {
    final prefs = await SharedPreferences.getInstance();
    final wasOngoing = prefs.getBool(_keyOngoingFeeding) ?? false;

    final now = DateTime.now();
    if (wasOngoing) {
      final ongoing = await DatabaseService().getOngoingFeeding();
      if (ongoing != null) {
        await DatabaseService().updateFeedingEntry(
          ongoing.copyWith(endTime: now),
        );
      }
      await prefs.setBool(_keyOngoingFeeding, false);
    } else {
      final entry = FeedingEntry(
        startTime: now,
        endTime: null,
        source: FeedingSource.breast,
      );
      await DatabaseService().insertFeedingEntry(entry);
      await prefs.setBool(_keyOngoingFeeding, true);
    }
    await _updateWidgetFromPrefs();
  }

  static Future<void> handleSleepFromWidget() async {
    final prefs = await SharedPreferences.getInstance();
    final wasOngoing = prefs.getBool(_keyOngoingSleep) ?? false;

    final now = DateTime.now();
    if (wasOngoing) {
      final ongoing = await DatabaseService().getOngoingSleep();
      if (ongoing != null) {
        await DatabaseService().updateSleepEntry(
          ongoing.copyWith(endTime: now),
        );
      }
      await prefs.setBool(_keyOngoingSleep, false);
    } else {
      final entry = SleepEntry(startTime: now);
      await DatabaseService().insertSleepEntry(entry);
      await prefs.setBool(_keyOngoingSleep, true);
    }
    await _updateWidgetFromPrefs();
  }

  // Sync app state → widget when app starts
  static Future<void> syncAppToWidget() async {
    final ongoingSleep = await DatabaseService().getOngoingSleep();
    final ongoingFeeding = await DatabaseService().getOngoingFeeding();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOngoingSleep, ongoingSleep != null);
    await prefs.setBool(_keyOngoingFeeding, ongoingFeeding != null);

    await _updateWidgetFromPrefs();
  }

  // Push prefs → Android widget UI
  static Future<void> _updateWidgetFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final sleep = prefs.getBool(_keyOngoingSleep) ?? false;
    final feeding = prefs.getBool(_keyOngoingFeeding) ?? false;

    await HomeWidget.saveWidgetData<String>('ongoing_sleep', sleep.toString());
    await HomeWidget.saveWidgetData<String>('ongoing_feeding', feeding.toString());
    await HomeWidget.updateWidget(
      name: 'WidgetProvider',
      androidName: 'WidgetProvider',
    );
  }
}
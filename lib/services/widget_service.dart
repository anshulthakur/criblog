// lib/services/widget_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:home_widget/home_widget.dart';
import '../models/sleep_entry.dart';
import '../models/feeding_entry.dart';
import 'database.dart';

class WidgetService {
  static const String _keyOngoingSleep = 'ongoing_sleep';
  static const String _keyOngoingFeeding = 'ongoing_feeding';
  static const String _keyFeedingSource = 'feeding_source';

  static Future<Map<String, dynamic>> handleFeedingFromWidget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasOngoing = prefs.getBool(_keyOngoingFeeding) ?? false;
      debugPrint('Handling feeding action, wasOngoing: $wasOngoing');

      final now = DateTime.now();
      if (wasOngoing) {
        final ongoing = await DatabaseService().getOngoingFeeding();
        if (ongoing != null) {
          await DatabaseService().updateFeedingEntry(
            ongoing.copyWith(endTime: now),
          );
          debugPrint('Updated feeding entry with endTime: $now');
        }
        await prefs.setBool(_keyOngoingFeeding, false);
        debugPrint('Set ongoing_feeding=false');
      } else {
        final entry = FeedingEntry(
          startTime: now,
          endTime: null,
          source: FeedingSource.breast,
        );
        await DatabaseService().insertFeedingEntry(entry);
        debugPrint('Inserted new feeding entry: $entry');
        await prefs.setBool(_keyOngoingFeeding, true);
        debugPrint('Set ongoing_feeding=true');
      }
      await _updateWidgetFromPrefs();
      return {
        'feeding': !wasOngoing,
        'sleep': prefs.getBool(_keyOngoingSleep) ?? false,
        'feedingSource': prefs.getString(_keyFeedingSource) ?? 'Breast',
      };
    } catch (e) {
      debugPrint('Error handling feeding from widget: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> handleSleepFromWidget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasOngoing = prefs.getBool(_keyOngoingSleep) ?? false;
      debugPrint('Handling sleep action, wasOngoing: $wasOngoing');

      final now = DateTime.now();
      if (wasOngoing) {
        final ongoing = await DatabaseService().getOngoingSleep();
        if (ongoing != null) {
          await DatabaseService().updateSleepEntry(
            ongoing.copyWith(endTime: now),
          );
          debugPrint('Updated sleep entry with endTime: $now');
        }
        await prefs.setBool(_keyOngoingSleep, false);
        debugPrint('Set ongoing_sleep=false');
      } else {
        final entry = SleepEntry(startTime: now);
        await DatabaseService().insertSleepEntry(entry);
        debugPrint('Inserted new sleep entry: $entry');
        await prefs.setBool(_keyOngoingSleep, true);
        debugPrint('Set ongoing_sleep=true');
      }
      await _updateWidgetFromPrefs();
      return {
        'feeding': prefs.getBool(_keyOngoingFeeding) ?? false,
        'sleep': !wasOngoing,
        'feedingSource': prefs.getString(_keyFeedingSource) ?? 'Breast',
      };
    } catch (e) {
      debugPrint('Error handling sleep from widget: $e');
      rethrow;
    }
  }

  static Future<void> syncAppToWidget() async {
    try {
      final ongoingSleep = await DatabaseService().getOngoingSleep();
      final ongoingFeeding = await DatabaseService().getOngoingFeeding();
      debugPrint('Syncing app to widget: sleep=${ongoingSleep != null}, feeding=${ongoingFeeding != null}');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyOngoingSleep, ongoingSleep != null);
      await prefs.setBool(_keyOngoingFeeding, ongoingFeeding != null);
      if (ongoingFeeding != null) {
        await prefs.setString(_keyFeedingSource, ongoingFeeding.source.toString().split('.').last);
      } else {
        await prefs.remove(_keyFeedingSource);
      }
      debugPrint('Prefs updated: sleep=${prefs.getBool(_keyOngoingSleep)}, feeding=${prefs.getBool(_keyOngoingFeeding)}, source=${prefs.getString(_keyFeedingSource)}');

      await _updateWidgetFromPrefs();
    } catch (e) {
      debugPrint('Error syncing app to widget: $e');
    }
  }

  static Future<void> _updateWidgetFromPrefs() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final prefs = await SharedPreferences.getInstance();
      final sleep = prefs.getBool(_keyOngoingSleep) ?? false;
      final feeding = prefs.getBool(_keyOngoingFeeding) ?? false;
      final feedingSource = prefs.getString(_keyFeedingSource) ?? 'Breast';

      debugPrint('Saving widget data: sleep=$sleep, feeding=$feeding, source=$feedingSource');
      await HomeWidget.saveWidgetData<bool>('ongoing_sleep', sleep);
      await HomeWidget.saveWidgetData<bool>('ongoing_feeding', feeding);
      await HomeWidget.saveWidgetData<String>('feeding_source', feedingSource);
      debugPrint('Updating widget with name=WidgetProvider');
      // Avoid multiple APPWIDGET_UPDATE broadcasts
      // const platform = MethodChannel('me.bhaad.criblog/widget');
      // await platform.invokeMethod('updateWidget').then((_) {
      //   debugPrint('Broadcast sent to update widget');
      // }).catchError((e) {
      //   debugPrint('Failed to send broadcast to update widget: $e');
      // });
      await Future.delayed(const Duration(milliseconds: 300));
      await HomeWidget.updateWidget(name: 'WidgetProvider');
      debugPrint('Broadcast sent to update widget via HomeWidget.updateWidget');

    } catch (e) {
      debugPrint('Widget update failed: $e');
    }
  }
}

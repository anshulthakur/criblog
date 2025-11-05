import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import 'services/database.dart';
import 'services/drive_service.dart';
import 'services/sync_service.dart';
import 'services/widget_service.dart';
import 'screens/home_screen.dart';
import 'screens/entries_screen.dart';
import 'screens/input_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/app_drawer.dart';

/// WorkManager dispatcher – runs in background
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("Background task started: $task, inputData: $inputData");
    try {
      switch (task) {
        case 'immediate-sync':
        case 'auto-sync':
          final syncService = SyncService();
          await syncService.sync(isBackground: true);
          debugPrint('Sync task completed: $task');
          break;
        case 'widget-feeding-toggle':
          await WidgetService.handleFeedingFromWidget();
          //await WidgetService.syncAppToWidget();
          debugPrint('Feeding toggle completed');
          break;
        case 'widget-sleep-toggle':
          await WidgetService.handleSleepFromWidget();
          //await WidgetService.syncAppToWidget();
          debugPrint('Sleep toggle completed');
          break;
        default:
          debugPrint("Unknown task: $task");
          return Future.value(false);
      }
      debugPrint('Background task completed: $task');
      return Future.value(true);
    } catch (e) {
      debugPrint('Background task failed: $task, error: $e');
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init DB
  await DatabaseService().database;

  // Init WorkManager
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true, // Enable debug logs
  );

  // --- MethodChannel: receives actions from Kotlin WidgetWorker ---
  const platform = MethodChannel('me.bhaad.criblog/widget');
  platform.setMethodCallHandler((call) async {
    try {
      debugPrint('MethodChannel received call: ${call.method}, arguments: ${call.arguments}');
      if (call.method == 'handleAction') {
        final type = call.arguments as String;
        debugPrint('MethodChannel handleAction: $type');
        Map<String, dynamic> result;
        if (type == 'feeding') {
          result = await WidgetService.handleFeedingFromWidget();
          debugPrint('Handled feeding action via MethodChannel');
        } else if (type == 'sleep') {
          result = await WidgetService.handleSleepFromWidget();
          debugPrint('Handled sleep action via MethodChannel');
        } else {
          debugPrint('Unknown action type: $type');
          return null;
        }
        // Trigger widget UI update after action
        //await WidgetService.syncAppToWidget();
        //debugPrint('Widget synced after MethodChannel action');
        return result; // Return state to MethodChannel
      } else {
        debugPrint('Unknown MethodChannel method: ${call.method}');
        return null;
      }
    } catch (e) {
      debugPrint('MethodChannel error: $e');
      rethrow;
    }
  });
  
  // Schedule auto-sync
  final syncService = SyncService();
  final prefs = await SharedPreferences.getInstance();
  final authorized = await syncService.isAuthorized;
  final interval = prefs.getInt('sync_auto_interval') ?? 180;
  if (authorized && interval > 0) {
    Workmanager().registerPeriodicTask(
      'auto-sync-task',
      'auto-sync',
      frequency: Duration(minutes: interval),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
  
  /*
  try {
    await HomeWidget.registerInteractivityCallback((uri) async {
      debugPrint('Widget tapped: $uri');
      return;
    });
  } catch (e, stack) {
    debugPrint('HomeWidget callback failed: $e');
  }
  */

  // Sync app state → widget on launch
  await WidgetService.syncAppToWidget();

  runApp(const CribLogApp());
}

class CribLogApp extends StatelessWidget {
  const CribLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CribLog',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (_) => const RootScaffold(child: HomeScreen()),
        '/entries': (_) => const RootScaffold(child: EntriesScreen()),
        '/settings': (_) => const RootScaffold(child: SettingsScreen()),
        '/input': (_) => const RootScaffold(child: InputScreen()),
      },
      onGenerateRoute: (settings) {
        // Fallback for invalid routes
        return MaterialPageRoute(
          builder: (_) => const RootScaffold(child: HomeScreen()),
        );
      },
    );
  }
}

class RootScaffold extends StatefulWidget {
  final Widget child;
  const RootScaffold({required this.child, super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  final syncService = SyncService();
  final driveService = DriveService();
  final List<String> _routeHistory = ['/'];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startTokenRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute != null && currentRoute != _routeHistory.last) {
      _routeHistory.add(currentRoute);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTokenRefresh() async {
    if (await syncService.isAuthorized) {
      await driveService.refreshToken();
      _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
        if (await syncService.isAuthorized) {
          await driveService.refreshToken();
        } else {
          _refreshTimer?.cancel();
        }
      });
    }
  }

  String _getTitle(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    return switch (route) {
      '/' => 'CribLog',
      '/entries' => 'Entries',
      '/settings' => 'Settings',
      '/input' => 'Log Activity',
      _ => 'CribLog',
    };
  }

  Future<void> _sync() async {
    try {
      await syncService.sync(forcePull: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final routeName = ModalRoute.of(context)?.settings.name;
        if (routeName == '/') {
          // Home screen → exit app
          SystemNavigator.pop();
          return true;
        } else if (routeName == '/settings') {
          // Settings → pop to previous screen
          if (_routeHistory.length > 1) {
            _routeHistory.removeLast();
            Navigator.pop(context);
            return false;
          }
        } else {
          // Entries, Input → go to Home
          _routeHistory.clear();
          _routeHistory.add('/');
          Navigator.pushReplacementNamed(context, '/');
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getTitle(context)),
          centerTitle: true,
          actions: [
            FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final prefs = snapshot.data!;
                final authorized = prefs.getBool('sync_drive_authorized') ?? false;
                final timestamp = prefs.getString('sync_last_timestamp');

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sync),
                      onPressed: authorized ? _sync : null,
                      tooltip: authorized ? 'Sync Now' : 'Authorize Drive in Settings',
                    ),
                    if (timestamp != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          DateTime.parse(timestamp).toLocal().toString().substring(11, 16),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        drawer: const AppDrawer(),
        drawerEnableOpenDragGesture: false,
        body: SafeArea(child: widget.child),
      ),
    );
  }
}

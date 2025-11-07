import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'services/database.dart';
import 'services/sync_service.dart';
import 'services/widget_service.dart';
import 'screens/home_screen.dart';
import 'screens/entries_screen.dart';
import 'screens/input_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/app_drawer.dart';
import 'app_state.dart';

/// WorkManager dispatcher – runs in background
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("Background task started: $task, inputData: $inputData");
    try {
      switch (task) {
        case 'immediate-sync':
          final syncService = SyncService();
          await syncService.sync(isBackground: true);
          debugPrint('Sync task completed: $task');
          break;
        case 'widget-feeding-toggle':
          await WidgetService.handleFeedingFromWidget();
          debugPrint('Feeding toggle completed');
          break;
        case 'widget-sleep-toggle':
          await WidgetService.handleSleepFromWidget();
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
  );

  // Create single AppState instance
  final appState = AppState();

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
        appState.notifyDatabaseChanged();
        return result;
      } else if (call.method == 'receiveWidgetUpdate') {
        debugPrint('MethodChannel: Received widget update: ${call.arguments}');
        appState.notifyDatabaseChanged();
        return null;
      } else {
        debugPrint('Unknown MethodChannel method: ${call.method}');
        return null;
      }
    } catch (e) {
      debugPrint('MethodChannel error: $e');
      rethrow;
    }
  });

  // Sync app state → widget on launch
  await WidgetService.syncAppToWidget(triggerUpdate: true, appState: appState);

  runApp(
    ChangeNotifierProvider(
      create: (_) => appState,
      child: const CribLogApp(),
    ),
  );
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
        '/': (_) => RootScaffold(child: HomeScreen()),
        '/entries': (_) => RootScaffold(child: const EntriesScreen()),
        '/settings': (_) => RootScaffold(child: const SettingsScreen()),
        '/input': (_) => RootScaffold(child: InputScreen()),
      },
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => RootScaffold(child: HomeScreen()),
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
  late final SyncService syncService;

  final List<String> _routeHistory = ['/'];

  @override
  void initState() {
    super.initState();
    syncService = SyncService(appState: Provider.of<AppState>(context, listen: false));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute != null && currentRoute != _routeHistory.last) {
      _routeHistory.add(currentRoute);
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
      await syncService.sync();
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
    return PopScope(
      canPop: false, // Prevent default pop
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return; // Already handled
        final routeName = ModalRoute.of(context)?.settings.name;
        debugPrint('PopScope: onPopInvokedWithResult, route: $routeName, didPop: $didPop, result: $result');
        if (routeName == '/') {
          // Move to background (like home button)
          SystemNavigator.pop(animated: true);
          return;
        } else if (routeName == '/settings') {
          if (_routeHistory.length > 1) {
            _routeHistory.removeLast();
            Navigator.pop(context);
          } else {
            _routeHistory.clear();
            _routeHistory.add('/');
            Navigator.pushReplacementNamed(context, '/');
          }
        } else {
          _routeHistory.clear();
          _routeHistory.add('/');
          Navigator.pushReplacementNamed(context, '/');
        }
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
                final lastSyncId = prefs.getString('last_sync_id');
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sync),
                      onPressed: _sync,
                      tooltip: 'Sync Now',
                    ),
                    if (lastSyncId != null && lastSyncId != '0')
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          DateTime.fromMillisecondsSinceEpoch(int.parse(lastSyncId))
                              .toLocal()
                              .toString()
                              .substring(11, 16),
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
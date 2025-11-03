import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/database.dart';
import 'services/sync_service.dart';
import 'screens/home_screen.dart';
import 'screens/entries_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/input_screen.dart';
import 'widgets/app_drawer.dart';
import 'services/widget_service.dart';
import 'package:home_widget/home_widget.dart';

/// WorkManager dispatcher – runs in background
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'auto-sync':
        final syncService = SyncService();
        try {
          await syncService.sync();
        } catch (e) {
          debugPrint('Auto-sync failed: $e');
        }
        break;
      case "widget-feeding-toggle":
        await WidgetService.handleFeedingFromWidget();
        break;
      case "widget-sleep-toggle":
        await WidgetService.handleSleepFromWidget();
        break;
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init DB
  await DatabaseService().database;

  // Init WorkManager
  Workmanager().initialize(callbackDispatcher);
  
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

  // --- MethodChannel: receives actions from Kotlin WidgetWorker ---
  /*
  const platform = MethodChannel('me.bhaad.criblog/widget');
  platform.setMethodCallHandler((call) async {
    if (call.method == 'handleAction') {
      final type = call.arguments as String;
      if (type == 'feeding') {
        await WidgetService.handleFeedingFromWidget();
      } else if (type == 'sleep') {
        await WidgetService.handleSleepFromWidget();
      }
    }
  });
  */

  // Sync app state → widget on launch
  //await WidgetService.syncAppToWidget();

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

class RootScaffold extends StatelessWidget {
  final Widget child;
  const RootScaffold({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final routeName = ModalRoute.of(context)?.settings.name;
        if (routeName != '/') {
          // Info screens (Entries, Settings, Input) → go to Home
          Navigator.pushReplacementNamed(context, '/');
          return false;
        }
        // Home screen → exit app
        SystemNavigator.pop();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getTitle(context)),
          centerTitle: true,
        ),
        drawer: const AppDrawer(),
        drawerEnableOpenDragGesture: false, // Disable swipe to open drawer
        body: SafeArea(child: child),
      ),
    );
  }

  String _getTitle(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    return switch (route) {
      '/' => 'Home',
      '/entries' => 'Entries',
      '/settings' => 'Settings',
      '/input' => 'Log Activity',
      _ => 'CribLog',
    };
  }
}

// // ------------------------------------------------------------------- Home

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});
//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   final ScrollController _scroll = ScrollController();
//   bool _showBar = true;
//   double _prev = 0.0;
//   final SyncService _syncService = SyncService();

//   @override
//   void initState() {
//     super.initState();
//     _scroll.addListener(() {
//       final cur = _scroll.offset;
//       if (cur > _prev && cur > 100) {
//         if (_showBar) setState(() => _showBar = false);
//       } else if (cur < _prev) {
//         if (!_showBar) setState(() => _showBar = true);
//       }
//       _prev = cur;
//     });
//   }

//   @override
//   void dispose() {
//     _scroll.dispose();
//     super.dispose();
//   }

//   Future<void> _sync() async {
//     try {
//       await _syncService.sync(forcePull: true);
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Synced successfully')),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Sync failed: $e')),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('CribLog'),
//         actions: [
//           FutureBuilder<SharedPreferences>(
//             future: SharedPreferences.getInstance(),
//             builder: (context, snapshot) {
//               if (!snapshot.hasData) return const SizedBox();
//               final prefs = snapshot.data!;
//               final authorized = prefs.getBool('sync_drive_authorized') ?? false;
//               final timestamp = prefs.getString('sync_last_timestamp');
              
//               return Row(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   IconButton(
//                     icon: const Icon(Icons.sync),
//                     onPressed: authorized ? _sync : null,
//                     tooltip: authorized ? 'Sync Now' : 'Authorize Drive in Settings',
//                   ),
//                   if (timestamp != null)
//                     Padding(
//                       padding: const EdgeInsets.only(right: 8),
//                       child: Text(
//                         DateTime.parse(timestamp).toLocal().toString().substring(11, 16),
//                         style: const TextStyle(fontSize: 12),
//                       ),
//                     ),
//                 ],
//               );
//             },
//           ),
//         ],
//       ),
//       drawer: const AppDrawer(),
//       body: Stack(
//         children: [
//           // ----- Dashboard area (will be filled later) -----
//           ListView(
//             controller: _scroll,
//             padding: const EdgeInsets.only(bottom: 80),
//             children: const [
//               Center(
//                 child: Padding(
//                   padding: EdgeInsets.all(32),
//                   child: Text(
//                     'Welcome to CribLog!\nDashboard coming soon.',
//                     textAlign: TextAlign.center,
//                     style: TextStyle(fontSize: 18),
//                   ),
//                 ),
//               ),
//               SizedBox(height: 1200), // scrollable filler
//             ],
//           ),

//           // ----- Collapsible floating bar -----
//           AnimatedPositioned(
//             duration: const Duration(milliseconds: 250),
//             bottom: _showBar ? 0 : -80,
//             left: 0,
//             right: 0,
//             child: const EntryBar(),
//           ),
//         ],
//       ),
//     );
//   }
// }
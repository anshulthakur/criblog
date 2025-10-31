import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:home_widget/home_widget.dart';
import 'services/database.dart';
import 'services/widget_service.dart';
import 'screens/entries_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/input_screen.dart';
import 'widgets/app_drawer.dart';
import 'widgets/entry_bar.dart';

/// WorkManager dispatcher – runs in background
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
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
  try {
    await HomeWidget.registerInteractivityCallback((uri) async {
      debugPrint('Widget tapped: $uri');
      return;
    });
  } catch (e, stack) {
    debugPrint('HomeWidget callback failed: $e');
  }
  

  // --- MethodChannel: receives actions from Kotlin WidgetWorker ---
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
      routes: {
        '/': (_) => const HomeScreen(),
        '/entries': (_) => const EntriesScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/input': (_) => const InputScreen(),
      },
      initialRoute: '/',
    );
  }
}
// ------------------------------------------------------------------- Home
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  bool _showBar = true;
  double _prev = 0.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final cur = _scroll.offset;
      if (cur > _prev && cur > 100) {
        if (_showBar) setState(() => _showBar = false);
      } else if (cur < _prev) {
        if (!_showBar) setState(() => _showBar = true);
      }
      _prev = cur;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Baby Tracker')),
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // ----- Dashboard area (will be filled later) -----
          ListView(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 80),
            children: const [
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Welcome to Baby Tracker!\nDashboard coming soon.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              SizedBox(height: 1200), // scrollable filler
            ],
          ),

          // ----- Collapsible floating bar -----
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            bottom: _showBar ? 0 : -80,
            left: 0,
            right: 0,
            child: const EntryBar(),
          ),
        ],
      ),
    );
  }
}
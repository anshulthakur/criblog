import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/entry_controller.dart';
import '../widgets/entry_bar.dart';
import '../app_state.dart';

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
    debugPrint('HomeScreen: initState');
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
    debugPrint('HomeScreen: Building');
    return ChangeNotifierProvider(
      create: (_) => EntryController(Provider.of<AppState>(context, listen: false)),
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          debugPrint('HomeScreen: Consumer rebuilt, appState: $appState');
          return Stack(
            children: [
              ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 80),
                children: const [
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Welcome to CribLog!\nDashboard coming soon.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  SizedBox(height: 1200), // Scrollable filler
                ],
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                bottom: _showBar ? 0 : -80,
                left: 0,
                right: 0,
                child: const EntryBar(),
              ),
            ],
          );
        },
      ),
    );
  }
}
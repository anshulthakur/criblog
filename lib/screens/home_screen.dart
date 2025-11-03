import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';
import '../widgets/entry_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  bool _showBar = true;
  double _prev = 0.0;
  final SyncService _syncService = SyncService();

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

  Future<void> _sync() async {
    try {
      await _syncService.sync(forcePull: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
  }
}
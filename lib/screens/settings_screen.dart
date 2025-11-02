import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../services/drive_service.dart';
import '../services/sync_service.dart';
import '../widgets/app_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SyncService _syncService = SyncService();
  final DriveService _driveService = DriveService();
  bool _driveAuthorized = false;
  int _autoSyncInterval = 180; // minutes (3 hours)
  final List<Map<String, dynamic>> _intervals = [
    {'label': '15 minutes', 'minutes': 15},
    {'label': '30 minutes', 'minutes': 30},
    {'label': '1 hour', 'minutes': 60},
    {'label': '3 hours', 'minutes': 180},
    {'label': '12 hours', 'minutes': 720},
    {'label': '1 day', 'minutes': 1440},
    {'label': '1 week', 'minutes': 10080},
  ];
  int _selectedInterval = 3;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final authorized = await _syncService.isAuthorized;
    setState(() {
      _driveAuthorized = authorized;
      _autoSyncInterval = prefs.getInt('sync_auto_interval') ?? 180;
      _selectedInterval = _intervals.indexWhere((i) => i['minutes'] == _autoSyncInterval);
      if (_selectedInterval == -1) _selectedInterval = 3;
    });
  }

  Future<void> _toggleDriveAuth() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (_driveAuthorized) {
        await _driveService.signOut();
        setState(() => _driveAuthorized = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Signed out from Google Drive')),
          );
        }
      } else {
        await _driveService.signIn();
        await _driveService.checkFolderAccess();
        setState(() => _driveAuthorized = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Drive authorized successfully')),
          );
        }
        await _updateAutoSync();
      }
    } catch (e) {
      await prefs.setBool('sync_drive_authorized', false);
      setState(() => _driveAuthorized = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authorization failed: $e')),
        );
      }
    }
  }

  Future<void> _updateAutoSync() async {
    final minutes = _intervals[_selectedInterval]['minutes'] as int;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_auto_interval', minutes);
    setState(() => _autoSyncInterval = minutes);

    Workmanager().cancelAll();
    if (_driveAuthorized && minutes > 0) {
      Workmanager().registerPeriodicTask(
        'auto-sync-task',
        'auto-sync',
        frequency: Duration(minutes: minutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Google Drive Sync'),
              subtitle: const Text('Backup and sync across devices'),
              value: _driveAuthorized,
              onChanged: (_) => _toggleDriveAuth(),
              secondary: _driveAuthorized
                  ? const Icon(Icons.cloud_done, color: Colors.green)
                  : const Icon(Icons.cloud_off, color: Colors.grey),
            ),
          ),
          if (_driveAuthorized)
            ListTile(
              title: const Text('Shared Folder'),
              subtitle: Text('Folder ID: ${_driveService.folderId.substring(0, 20)}...'),
              trailing: const Icon(Icons.folder),
              onTap: () {
                // TODO: Copy folder ID to clipboard
              },
            ),
          const Divider(),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  title: const Text('Auto-Sync Interval'),
                  subtitle: const Text('Sync in background'),
                  trailing: DropdownButton<int>(
                    value: _selectedInterval,
                    items: _intervals.asMap().entries.map((entry) {
                      return DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value['label']),
                      );
                    }).toList(),
                    onChanged: _driveAuthorized
                        ? (value) {
                            setState(() => _selectedInterval = value!);
                            _updateAutoSync();
                          }
                        : null,
                  ),
                ),
                if (_driveAuthorized)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Next sync: ${_intervals[_selectedInterval]['label']}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          FutureBuilder<SharedPreferences>(
            future: SharedPreferences.getInstance(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final prefs = snapshot.data!;
              final timestamp = prefs.getString('sync_last_timestamp');
              final result = prefs.getString('sync_last_result');
              return Card(
                child: ListTile(
                  title: const Text('Last Sync'),
                  subtitle: Text(
                    timestamp != null
                        ? 'At ${DateTime.parse(timestamp).toLocal().toString().substring(0, 16)}'
                        : 'Never',
                  ),
                  trailing: timestamp != null && result == 'success'
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.error, color: Colors.red),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
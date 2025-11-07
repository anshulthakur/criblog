import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/drive_service.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SyncService _syncService = SyncService();
  final DriveService _driveService = DriveService();
  bool _isSigningIn = false;
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('User Account'),
            subtitle: FutureBuilder<String?>(
              future: _driveService.currentUserEmail,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Text('Signed in as ${snapshot.data}');
                }
                return const Text('Sign in to identify your account');
              },
            ),
            trailing: FutureBuilder<String?>(
              future: _driveService.currentUserEmail,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return ElevatedButton(
                    onPressed: _isSigningIn ? null : _signOut,
                    child: const Text('Sign Out'),
                  );
                }
                return ElevatedButton(
                  onPressed: _isSigningIn ? null : _signIn,
                  child: const Text('Login using Google'),
                );
              },
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Manual Sync'),
            subtitle: const Text('Sync data with Google Sheets'),
            trailing: ElevatedButton(
              onPressed: _isSyncing ? null : _manualSync,
              child: const Text('Sync Now'),
            ),
          ),
        ),
        const Divider(),
        FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            final prefs = snapshot.data!;
            final lastSyncId = prefs.getString('last_sync_id');
            final result = prefs.getString('sync_last_result');
            return Card(
              child: ListTile(
                title: const Text('Last Sync'),
                subtitle: Text(
                  lastSyncId != null && lastSyncId != '0'
                      ? 'At ${DateTime.fromMillisecondsSinceEpoch(int.parse(lastSyncId)).toLocal().toString().substring(0, 16)}'
                      : 'Never',
                ),
                trailing: lastSyncId != null && result == 'success'
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.error, color: Colors.red),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _signIn() async {
    setState(() => _isSigningIn = true);
    try {
      await _driveService.signInAndStoreUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully')),
        );
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
      }
    }
    setState(() => _isSigningIn = false);
  }

  Future<void> _signOut() async {
    setState(() => _isSigningIn = true);
    try {
      await _driveService.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out successfully')),
        );
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-out failed: $e')),
        );
      }
    }
    setState(() => _isSigningIn = false);
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);
    try {
      await _syncService.sync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed successfully')),
        );
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
    setState(() => _isSyncing = false);
  }
}
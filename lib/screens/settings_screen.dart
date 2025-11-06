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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Google Drive Sync'),
            subtitle: const Text('Backup and sync across devices'),
            trailing: FutureBuilder<bool>(
              future: _syncService.isAuthorized,
              builder: (context, snapshot) {
                final isAuthorized = snapshot.data ?? false;
                return ElevatedButton(
                  onPressed: _isSigningIn ? null : _authorize,
                  child: Text(isAuthorized ? 'Re-authorize' : 'Authorize'),
                );
              },
            ),
          ),
        ),
        FutureBuilder<bool>(
          future: _syncService.isAuthorized,
          builder: (context, snapshot) {
            final isAuthorized = snapshot.data ?? false;
            return Visibility(
              visible: isAuthorized,
              child: Card(
                child: ListTile(
                  title: const Text('Sign Out'),
                  subtitle: const Text('Disconnect from Google Drive'),
                  trailing: ElevatedButton(
                    onPressed: _isSigningIn ? null : _signOut,
                    child: const Text('Sign Out'),
                  ),
                ),
              ),
            );
          },
        ),
        FutureBuilder<bool>(
          future: _syncService.isAuthorized,
          builder: (context, snapshot) {
            final isAuthorized = snapshot.data ?? false;
            return Visibility(
              visible: isAuthorized,
              child: ListTile(
                title: const Text('Shared Folder'),
                subtitle: Text('Folder ID: ${_driveService.folderId.substring(0, 20)}...'),
                trailing: const Icon(Icons.folder),
                onTap: () {
                  // TODO: Copy folder ID to clipboard
                },
              ),
            );
          },
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
    );
  }

  Future<void> _authorize() async {
    setState(() => _isSigningIn = true);
    try {
      await _driveService.signIn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drive authorized successfully')),
        );
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authorization failed: $e')),
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
          const SnackBar(content: Text('Signed out from Google Drive')),
        );
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
    }
    setState(() => _isSigningIn = false);
  }
}
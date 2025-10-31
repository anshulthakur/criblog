// lib/widgets/app_drawer.dart
import 'package:flutter/material.dart';
import '../screens/input_screen.dart';   // <-- NEW

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(
              'Baby Tracker',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () => Navigator.popAndPushNamed(context, '/'),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle),
            title: const Text('Log Activity'),   // NEW MENU ITEM
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InputScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.list),
            title: const Text('View Entries'),
            onTap: () => Navigator.popAndPushNamed(context, '/entries'),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () => Navigator.popAndPushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }
}
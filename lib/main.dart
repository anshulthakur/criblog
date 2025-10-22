import 'package:flutter/material.dart';

void main() {
  runApp(const CribLog());
}

class CribLog extends StatelessWidget {
  const CribLog({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Hello World!'),
        ),
      ),
    );
  }
}

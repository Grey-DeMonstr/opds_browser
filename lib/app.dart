import 'package:flutter/material.dart';

/// Root application widget. A minimal placeholder for the scaffold step;
/// theming, Riverpod, and go_router are wired up in later steps.
class OpdsBrowserApp extends StatelessWidget {
  const OpdsBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OPDS Browser',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('OPDS Browser')),
      ),
    );
  }
}

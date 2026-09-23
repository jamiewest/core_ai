import 'package:flutter/material.dart';

import 'demos.dart';

void main() => runApp(const CoreMLExampleApp());

/// Demonstrates the core_ml plugin with five tiny bundled models.
class CoreMLExampleApp extends StatelessWidget {
  /// Creates the app.
  const CoreMLExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: 'core_ml',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomePage(),
    );
  }
}

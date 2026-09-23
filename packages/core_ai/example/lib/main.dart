import 'package:flutter/material.dart';

import 'home_page.dart';

void main() => runApp(const CoreAIExampleApp());

/// Demonstrates the core_ai plugin with four small bundled models.
class CoreAIExampleApp extends StatelessWidget {
  const CoreAIExampleApp({super.key});

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3D5AFE),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(height: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Core AI',
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const HomePage(),
  );
}

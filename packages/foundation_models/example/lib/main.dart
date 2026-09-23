import 'package:flutter/material.dart';

import 'chat_page.dart';

void main() => runApp(const FoundationModelsExampleApp());

/// Demonstrates the foundation_models plugin with a small chat.
class FoundationModelsExampleApp extends StatelessWidget {
  const FoundationModelsExampleApp({super.key});

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6D4AFF),
      brightness: brightness,
    ),
    textTheme: const TextTheme(bodyMedium: TextStyle(height: 1.4)),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Foundation Models',
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const ChatPage(),
  );
}

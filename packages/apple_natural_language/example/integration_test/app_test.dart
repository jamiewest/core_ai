// Drives the example app against the real framework:
//
//   cd example && flutter test integration_test/app_test.dart -d macos

import 'package:apple_natural_language_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  testWidgets('analyzes the sample text and finds similar words', (
    tester,
  ) async {
    await tester.pumpWidget(const NaturalLanguageExampleApp());

    await waitFor(tester, find.text('Tim Cook · PersonalName'));
    expect(find.text('Paris · PlaceName'), findsOneWidget);
    expect(find.textContaining('positive'), findsOneWidget);
    expect(find.textContaining('en ('), findsOneWidget);

    final button = find.text('Similar words');
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button);
    await waitFor(tester, find.text('Nearest in the word embedding'));
    // Neighbor chips read "word (0.123)".
    expect(find.textContaining(RegExp(r'^\w+ \(\d\.\d{3}\)$')), findsWidgets);
  });
}

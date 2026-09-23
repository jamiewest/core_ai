// Drives the example chat against the real model:
//
//   cd example && flutter test integration_test/app_test.dart -d macos

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_models/foundation_models.dart';
import 'package:foundation_models_example/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps until [ready] is true, for at most [seconds].
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() ready, {
    int seconds = 60,
  }) async {
    for (var i = 0; i < seconds * 10 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: 'timed out waiting');
  }

  testWidgets('answers a prompt in the chat', (tester) async {
    if (!(await SystemLanguageModel.defaultModel.availability()).isAvailable) {
      markTestSkipped('Apple Intelligence is not available here.');
      return;
    }
    await tester.pumpWidget(const FoundationModelsExampleApp());

    // The session is ready once the info bar appears and input is enabled.
    await waitFor(
      tester,
      () => find.textContaining('On device').evaluate().isNotEmpty,
    );
    await waitFor(
      tester,
      () => tester.widget<TextField>(find.byType(TextField)).enabled ?? false,
    );

    await tester.enterText(find.byType(TextField), 'Say hello in three words.');
    await tester.tap(find.byTooltip('Send'));

    // The model's bubble fills in as snapshots stream back.
    await waitFor(
      tester,
      () => find.byType(SelectableText).evaluate().length >= 2,
    );
    await waitFor(tester, () {
      final bubbles = find.byType(SelectableText).evaluate();
      if (bubbles.length < 2) return false;
      final last = bubbles.last.widget as SelectableText;
      return (last.data ?? '').length > 2;
    });

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    expect(await FoundationModels.liveHandleCount(), 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

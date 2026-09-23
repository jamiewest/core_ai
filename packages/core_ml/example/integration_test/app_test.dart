// Runs every demo of the example app against the real Core ML framework:
//
//   cd example && flutter test integration_test/app_test.dart -d macos

import 'package:core_ml/core_ml.dart';
import 'package:core_ml_example/demos.dart';
import 'package:core_ml_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every demo runs without errors', (tester) async {
    final previousHitTestSetting = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previousHitTestSetting;
    });
    await tester.pumpWidget(const CoreMLExampleApp());
    await tester.pumpAndSettle();

    for (final demo in demos) {
      final card = find.widgetWithText(Card, demo.title);
      final button = find.descendant(
        of: card,
        matching: find.byType(FilledButton),
      );
      await tester.scrollUntilVisible(
        button,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget, reason: demo.title);
      await tester.tap(button);
      await tester.pump();
      // Predictions run natively; give them real time to finish.
      for (var tick = 0; tick < 200; tick++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final output = find.descendant(
        of: card,
        matching: find.byType(SelectableText),
      );
      expect(
        output,
        findsOneWidget,
        reason: '${demo.title} produced no output',
      );
      final text = tester.widget<SelectableText>(output).data!;
      expect(text, isNotEmpty, reason: demo.title);
      expect(text, isNot(startsWith('Error:')), reason: demo.title);
    }
    await tester.pumpAndSettle();

    // Cards scrolled off screen are disposed, so check what each produced
    // by running the demos directly as well.
    expect(await demos[0].run(), contains('y = [3.0, 5.0, 7.0]'));
    expect(await demos[2].run(), contains('predicted: bee'));
    expect(await demos[3].run(), contains('B, G, R at (0, 0): [200.0'));
    expect(await demos[4].run(), contains('state: [3.0, 6.0, 9.0]'));
    expect(await CoreML.liveHandleCount(), 0);
  });
}

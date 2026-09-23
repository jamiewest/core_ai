import 'package:apple_translation/apple_translation.dart';
import 'package:apple_translation_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    final live = await Translation.liveHandleCount();
    await Translation.releaseAll();
    expect(live, 0, reason: 'the example leaked a native session');
  });

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var tick = 0; tick < 600 && !ready(); tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: 'the example did not finish within 60 s');
  }

  testWidgets('translates text and streams each line through the app', (
    tester,
  ) async {
    if (await const LanguageAvailability().status(from: 'en', to: 'es') !=
        LanguageStatus.installed) {
      markTestSkipped('English to Spanish language packs are not installed.');
      return;
    }
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
    await tester.pumpWidget(const TranslationExampleApp());

    final translate = find.byKey(const ValueKey('translate'));
    await waitFor(
      tester,
      () =>
          translate.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(translate).onPressed != null,
    );
    await tester.ensureVisible(translate);
    await tester.pumpAndSettle();
    await tester.tap(translate);
    await waitFor(
      tester,
      () =>
          find.byType(SelectableText).evaluate().isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('Hola'),
    );
    expect(await Translation.liveHandleCount(), 0);

    final input = find.byKey(const ValueKey('source-text'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'Good morning\nThank you');
    final batch = find.byKey(const ValueKey('translate-lines'));
    await tester.ensureVisible(batch);
    await tester.pumpAndSettle();
    await tester.tap(batch);
    await waitFor(
      tester,
      () =>
          find.byType(SelectableText).evaluate().length == 2 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    final results = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data);
    expect(
      results,
      unorderedEquals([contains('Buenos días'), contains('Gracias')]),
    );
    expect(find.text('Line 1: Good morning'), findsOneWidget);
    expect(find.text('Line 2: Thank you'), findsOneWidget);
    expect(find.byKey(const ValueKey('translation-error')), findsNothing);
    expect(await Translation.liveHandleCount(), 0);
  });
}

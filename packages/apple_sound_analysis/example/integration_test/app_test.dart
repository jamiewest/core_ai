import 'package:apple_sound_analysis/apple_sound_analysis.dart';
import 'package:apple_sound_analysis_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async => expect(await SoundAnalyzer.cancelAll(), 0));

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var tick = 0; tick < 600 && !done(); tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue, reason: 'analysis did not finish within 60 seconds');
  }

  testWidgets('classifies speech, custom tone, and PCM through the example', (
    tester,
  ) async {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
    await tester.pumpWidget(const SoundAnalysisExampleApp());
    final speech = find.byKey(const ValueKey('speech'));
    await waitFor(tester, () => speech.evaluate().isNotEmpty);

    Future<void> run(String key, String label) async {
      final button = find.byKey(ValueKey(key));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      await waitFor(
        tester,
        () => find.text('Analysis complete.').evaluate().isNotEmpty,
      );
      expect(
        find.textContaining(RegExp('^$label [0-9]+\\.[0-9]%')),
        findsWidgets,
      );
      expect(find.byKey(const ValueKey('analysis-error')), findsNothing);
      expect(await SoundAnalyzer.cancelAll(), 0);
    }

    await run('speech', 'speech');
    final toggle = find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await run('tone', 'tone');
    await run('pcm', 'tone');
    // Dispose the example, which removes its extracted fixture directory.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

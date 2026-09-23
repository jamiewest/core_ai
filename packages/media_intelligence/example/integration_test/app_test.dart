// Drives the example against the real framework:
//
//   cd example && flutter test integration_test/app_test.dart -d macos

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_intelligence/media_intelligence.dart';
import 'package:media_intelligence_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 1200 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget);
  }

  testWidgets('finds highlights and scans the sample image', (tester) async {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);

    await tester.pumpWidget(const MediaIntelligenceExampleApp());
    await waitFor(tester, find.text('Find highlights'));

    await tester.tap(find.text('Find highlights'));
    await waitFor(tester, find.textContaining('Key frame: '));
    expect(find.textContaining('Highlight: '), findsWidgets);
    expect(find.byKey(const Key('highlight-timeline')), findsOneWidget);

    final scan = find.text('Scan sample image');
    await tester.ensureVisible(scan);
    await tester.pumpAndSettle();
    await tester.tap(scan);
    await waitFor(tester, find.text('scene: 0 faces'));
    expect(await MediaIntelligence.liveHandleCount(), 0);
  });
}

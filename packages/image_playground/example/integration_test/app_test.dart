// Drives the example against the real framework:
//
//   cd example && flutter test integration_test/app_test.dart -d macos
//
// It opens Apple's sheet without a prompt, so nothing is generated, then
// cancels it from the app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_playground/image_playground.dart';
import 'package:image_playground_example/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget);
  }

  testWidgets('opens the system sheet and cancels it', (tester) async {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);

    await tester.pumpWidget(const ImagePlaygroundExampleApp());
    await waitFor(tester, find.text('Ready.'));
    expect(find.text('illustration'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Open Image Playground'));
    await waitFor(tester, find.text('Waiting for Image Playground…'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Cancel'));
    await waitFor(tester, find.text('Cancelled.'));
    expect(await ImagePlayground.liveHandleCount(), 0);
  });
}

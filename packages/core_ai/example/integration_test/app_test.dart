// Drives the example app's demos end to end on a Core AI device:
//
//   cd example && flutter test integration_test/app_test.dart -d macos

import 'package:core_ai/core_ai.dart';
import 'package:core_ai_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  testWidgets('runs every demo', (tester) async {
    if (!await CoreAI.isSupported()) {
      markTestSkipped('Core AI is not available here.');
      return;
    }
    await tester.pumpWidget(const CoreAIExampleApp());

    await settle(tester, find.text('Run'));
    await tester.tap(find.text('Run'));
    await settle(tester, find.textContaining('y = [3.00, 5.00, 7.00]'));

    await tester.tap(find.text('Stateful'));
    await settle(tester, find.text('Add x = [1, 2, 3]'));
    await tester.tap(find.text('Add x = [1, 2, 3]'));
    await settle(tester, find.textContaining('total = [1.00, 2.00, 3.00]'));
    await tester.tap(find.text('Add x = [1, 2, 3]'));
    await settle(tester, find.textContaining('total = [2.00, 4.00, 6.00]'));

    await tester.tap(find.text('Image'));
    await settle(tester, find.bySemanticsLabel('Run with this color'));
    await tester.tap(find.bySemanticsLabel('Run with this color').first);
    await settle(tester, find.textContaining('first pixel (B, G, R, A)'));

    await tester.tap(find.text('Matmul'));
    await settle(tester, find.text('Encode on a ComputeStream'));
    await tester.tap(find.text('Encode on a ComputeStream'));
    await settle(tester, find.textContaining('a + 1 =\n'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(await CoreAI.liveHandleCount(), 0);
  });
}

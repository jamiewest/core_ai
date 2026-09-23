// Checks graceful behavior where Core AI is unavailable: the iOS Simulator
// (whose SDK has no CoreAI.framework) and iOS/macOS before 27. Run with:
//
//   cd example && flutter test integration_test/unsupported_test.dart -d <id>

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports Core AI as unsupported without crashing', (_) async {
    if (await CoreAI.isSupported()) {
      markTestSkipped('Core AI is available here; run core_ai_test.dart.');
      return;
    }
    expect(await CoreAI.platformVersion(), isNotEmpty);
    expect(
      await CoreAI.assetPath('assets/models/affine.aimodel'),
      endsWith('affine.aimodel'),
    );

    await expectLater(
      AIModel.loadAsset('assets/models/affine.aimodel'),
      throwsA(
        isA<CoreAIException>().having(
          (e) => e.code,
          'code',
          CoreAIErrorCode.unsupported,
        ),
      ),
    );
    await expectLater(
      CoreAI.deviceArchitectureName(),
      throwsA(isA<CoreAIException>()),
    );

    // Pure-Dart value types keep working.
    expect(NDArray.float16([1.5]).toDoubleList(), [1.5]);
  });
}

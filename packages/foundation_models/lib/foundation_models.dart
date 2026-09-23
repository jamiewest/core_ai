/// Flutter bindings for Apple's Foundation Models framework: the Apple
/// Intelligence language models (iOS 26+ / macOS 26+).
///
/// * [SystemLanguageModel] runs entirely on device;
///   [PrivateCloudComputeLanguageModel] (iOS 27+) runs on Apple's servers and
///   is larger.
/// * [LanguageModelSession] holds a conversation: [LanguageModelSession.respond],
///   [LanguageModelSession.streamResponse], guided generation with a
///   [GenerationSchema], and tools the model can call.
///
/// ```dart
/// if ((await SystemLanguageModel.defaultModel.availability()).isAvailable) {
///   final session = await LanguageModelSession.create(
///     instructions: 'Answer in one short sentence.',
///   );
///   final response = await session.respond('Why is the sky blue?');
///   print(response.content);
///   await session.dispose();
/// }
/// ```
library;

export 'src/content.dart';
export 'src/errors.dart'
    show FoundationModelsErrorCode, FoundationModelsException;
export 'src/models.dart';
export 'src/native_resource.dart' show NativeResource;
export 'src/options.dart';
export 'src/prompt.dart';
export 'src/schema.dart';
export 'src/session.dart';
export 'src/tools.dart';
export 'src/transcript.dart';

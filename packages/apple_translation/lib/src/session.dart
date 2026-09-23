import 'dart:async';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'models.dart';
import 'native_resource.dart';

/// Translates text between two installed languages (`TranslationSession`).
///
/// Sessions are created with Apple's
/// `TranslationSession(installedSource:target:)` (iOS 26 / macOS 26), which
/// needs no SwiftUI view but only works with languages that are already
/// downloaded. It never downloads languages or shows system UI:
/// [canRequestDownloads] is false.
///
/// ```dart
/// final session = await TranslationSession.create(
///   installedSource: 'en',
///   target: 'es',
/// );
/// final response = await session.translate('Hello, how are you?');
/// print(response.targetText); // Hola, ¿cómo estás?
/// await session.dispose();
/// ```
final class TranslationSession extends NativeResource {
  TranslationSession._(SessionInfoMessage info)
    : sourceLanguage = info.sourceLanguage == null
          ? null
          : Language.fromMessage(info.sourceLanguage!),
      targetLanguage = info.targetLanguage == null
          ? null
          : Language.fromMessage(info.targetLanguage!),
      canRequestDownloads = info.canRequestDownloads,
      preferredStrategy = info.preferredStrategy == null
          ? null
          : TranslationStrategy.fromMessage(info.preferredStrategy!),
      super(info.handle);

  /// Creates a session that translates from [installedSource] into [target]
  /// (`TranslationSession(installedSource:target:preferredStrategy:)`).
  ///
  /// Both are BCP 47 identifiers such as `en` or `zh-Hant`. With a null
  /// [target], the system picks one from the user's preferred languages.
  /// [preferredStrategy] needs iOS 26.4 / macOS 26.4.
  ///
  /// Creating a session always succeeds for valid identifiers. Check
  /// [isReady] or [LanguageStatus] first: translating a pair that is not
  /// installed throws [TranslationErrorCode.notInstalled], and an
  /// unsupported pair throws one of the `unsupported...` codes.
  ///
  /// Throws [TranslationErrorCode.unsupported] before iOS 26 / macOS 26.
  static Future<TranslationSession> create({
    required String installedSource,
    String? target,
    TranslationStrategy? preferredStrategy,
  }) async {
    final host = TranslationBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.createSession(
        installedSource,
        target,
        preferredStrategy?.toMessage(),
      ),
    );
    return TranslationSession._(info);
  }

  /// The language this session translates from.
  final Language? sourceLanguage;

  /// The language this session translates into, or null when the system
  /// picks it.
  final Language? targetLanguage;

  /// Whether this session may show the system's download UI. Always false
  /// for sessions created with [create].
  final bool canRequestDownloads;

  /// The session's strategy, or null before iOS 26.4 / macOS 26.4.
  final TranslationStrategy? preferredStrategy;

  /// Whether the session's languages are installed and it can translate
  /// right away (`isReady`). False for unsupported pairs.
  Future<bool> get isReady =>
      guardPlatformCall(() => bindings.host.isReady(handle));

  /// Translates [text] (`translate(_:)`).
  ///
  /// Empty text throws [TranslationErrorCode.nothingToTranslate].
  /// Whitespace-only text is returned unchanged. Text in another language
  /// than [sourceLanguage] is not detected and usually comes back unchanged.
  Future<TranslationResponse> translate(String text) =>
      _translate(TranslationRequest(text));

  /// Translates text made of [segments], leaving the ones marked with
  /// [TextSegment.skip] untouched (`translate(_: AttributedString)`,
  /// iOS 26.4 / macOS 26.4).
  ///
  /// The response's [TranslationResponse.targetSegments] shows which parts
  /// of the translation were skipped.
  Future<TranslationResponse> translateSegments(List<TextSegment> segments) =>
      _translate(TranslationRequest.segments(segments));

  Future<TranslationResponse> _translate(TranslationRequest request) async {
    final message = await guardPlatformCall(
      () => bindings.host.translate(handle, request.toMessage()),
    );
    return TranslationResponse.fromMessage(message);
  }

  /// Translates every request and returns the responses in request order
  /// (`translations(from:)`).
  ///
  /// Unlike [translate], an empty string inside a batch translates to an
  /// empty string instead of throwing.
  Future<List<TranslationResponse>> translations(
    List<TranslationRequest> requests,
  ) async {
    final messages = await guardPlatformCall(
      () => bindings.host.translations(handle, [
        for (final request in requests) request.toMessage(),
      ]),
    );
    return messages.map(TranslationResponse.fromMessage).toList();
  }

  /// Streams a response for each request as soon as it is translated
  /// (`translate(batch:)`). Match responses to requests with
  /// [TranslationRequest.clientIdentifier].
  ///
  /// The batch starts when the stream is listened to. Cancelling the
  /// subscription stops it without affecting the session.
  Stream<TranslationResponse> translateBatch(
    List<TranslationRequest> requests,
  ) {
    final messages = [for (final request in requests) request.toMessage()];
    final requestId = bindings.nextRequestId();
    final sessionHandle = handle;
    late final StreamController<TranslationResponse> controller;
    var finished = false;
    void finish() {
      finished = true;
      bindings.unregisterBatch(requestId);
    }

    controller = StreamController<TranslationResponse>(
      onListen: () async {
        bindings.registerBatch(
          requestId,
          _BatchSink(controller, onFinished: finish),
        );
        try {
          await guardPlatformCall(
            () => bindings.host.startBatch(sessionHandle, requestId, messages),
          );
        } on Object catch (error, stack) {
          finish();
          if (!controller.isClosed) {
            controller.addError(error, stack);
            await controller.close();
          }
        }
      },
      onCancel: () async {
        if (finished) return;
        finish();
        await guardPlatformCall(() => bindings.host.cancelRequest(requestId));
      },
    );
    return controller.stream;
  }

  /// Makes sure the session's languages are ready (`prepareTranslation()`).
  ///
  /// Sessions from [create] cannot download, so this completes when the pair
  /// is installed and throws otherwise.
  Future<void> prepareTranslation() =>
      guardPlatformCall(() => bindings.host.prepareTranslation(handle));

  /// Cancels in-flight work (`cancel()`). This is permanent: every later
  /// call on this session throws [TranslationErrorCode.alreadyCancelled].
  /// Create a new session to translate again.
  Future<void> cancel() =>
      guardPlatformCall(() => bindings.host.cancelSession(handle));

  @override
  String toString() =>
      'TranslationSession($sourceLanguage -> ${targetLanguage ?? 'auto'}'
      '${isDisposed ? ', disposed' : ''})';
}

class _BatchSink implements BatchSink {
  _BatchSink(this._controller, {required void Function() onFinished})
    : _onFinished = onFinished;

  final StreamController<TranslationResponse> _controller;
  final void Function() _onFinished;

  @override
  void onResponse(TranslationResponseMessage response) {
    if (_controller.isClosed) return;
    _controller.add(TranslationResponse.fromMessage(response));
  }

  @override
  void onDone() {
    _onFinished();
    if (!_controller.isClosed) _controller.close();
  }

  @override
  void onError(ErrorMessage error) {
    _onFinished();
    if (_controller.isClosed) return;
    _controller
      ..addError(
        TranslationException(
          TranslationErrorCode.fromWire(error.code),
          error.message,
          details: error.details,
        ),
      )
      ..close();
  }
}

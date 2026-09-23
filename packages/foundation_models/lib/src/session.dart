import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bindings.dart';
import 'content.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'models.dart';
import 'native_resource.dart';
import 'options.dart';
import 'prompt.dart';
import 'schema.dart';
import 'tools.dart';
import 'transcript.dart';

/// A completed response (Apple's `LanguageModelSession.Response`).
@immutable
final class ModelResponse<T> {
  /// Creates a response.
  const ModelResponse({
    required this.content,
    required this.entries,
    required this.usage,
  });

  /// The generated content: a [String], or [GeneratedContent] for guided
  /// generation.
  final T content;

  /// The transcript entries this request added.
  final List<TranscriptEntry> entries;

  /// How many tokens the request used (zero before iOS 27 / macOS 27).
  final Usage usage;

  @override
  String toString() => 'ModelResponse($content)';
}

/// A partial response while streaming.
///
/// [content] is **cumulative**: each snapshot carries everything generated so
/// far, not just the new part. Use [delta] for the new text.
@immutable
final class ResponseSnapshot<T> {
  /// Creates a snapshot.
  const ResponseSnapshot({
    required this.content,
    required this.delta,
    required this.isComplete,
    required this.usage,
  });

  /// Everything generated so far.
  final T content;

  /// What this snapshot added, for text responses.
  final String delta;

  /// Whether generation has finished.
  final bool isComplete;

  /// Tokens used so far (zero before iOS 27 / macOS 27).
  final Usage usage;

  @override
  String toString() => 'ResponseSnapshot($content)';
}

/// How a session's transcript behaves when a request fails (Apple's
/// `TranscriptErrorHandlingPolicy`). Needs iOS 27 / macOS 27.
enum TranscriptErrorHandlingPolicy {
  /// Remove the failed request from the transcript.
  revertTranscript,

  /// Keep it.
  preserveTranscript;

  TranscriptPolicyMessage _toMessage() => TranscriptPolicyMessage.values[index];
}

/// How the user felt about a response, for [LanguageModelSession.logFeedback].
enum FeedbackSentiment {
  /// The response was good.
  positive,

  /// The response was bad.
  negative,

  /// Neither.
  neutral;

  FeedbackSentimentMessage _toMessage() =>
      FeedbackSentimentMessage.values[index];
}

/// What was wrong with a response.
enum FeedbackIssueCategory {
  /// It did not help.
  unhelpful,

  /// It was too long.
  tooVerbose,

  /// It ignored the instructions.
  didNotFollowInstructions,

  /// It was wrong.
  incorrect,

  /// It was biased or stereotyping.
  stereotypeOrBias,

  /// It was suggestive or sexual.
  suggestiveOrSexual,

  /// It was vulgar or offensive.
  vulgarOrOffensive,

  /// Guardrails fired when they should not have.
  triggeredGuardrailUnexpectedly;

  FeedbackIssueCategoryMessage _toMessage() =>
      FeedbackIssueCategoryMessage.values[index];
}

/// One reported issue.
@immutable
final class FeedbackIssue {
  /// Creates an issue.
  const FeedbackIssue(this.category, {this.explanation});

  /// What kind of problem it was.
  final FeedbackIssueCategory category;

  /// The user's own words, if any.
  final String? explanation;
}

/// A conversation with a language model (Apple's `LanguageModelSession`).
///
/// A session keeps the transcript of everything said so far and feeds it back
/// on each request, so the model has context. One session handles one request
/// at a time.
///
/// ```dart
/// final session = await LanguageModelSession.create(
///   instructions: 'You are a helpful assistant. Answer briefly.',
/// );
/// final response = await session.respond('What is the capital of France?');
/// print(response.content);
/// await session.dispose();
/// ```
final class LanguageModelSession extends NativeResource implements ToolHost {
  LanguageModelSession._(super.handle, this._tools) {
    bindings.registerToolHost(handle, this);
  }

  /// Starts a session.
  ///
  /// * [model] defaults to the on-device model.
  /// * [instructions] set the model's role and rules. They take priority over
  ///   prompts, so never build them from untrusted input.
  /// * [tools] are Dart functions the model may call.
  /// * [builtInTools] are Apple's own tools (iOS 27 / macOS 27).
  /// * [transcript] resumes an earlier conversation, instead of
  ///   [instructions].
  static Future<LanguageModelSession> create({
    LanguageModel model = SystemLanguageModel.defaultModel,
    String? instructions,
    List<Tool> tools = const [],
    List<BuiltInTool> builtInTools = const [],
    Transcript? transcript,
    TranscriptErrorHandlingPolicy? transcriptErrorHandlingPolicy,
  }) async {
    final host = FoundationModelsBindings.instance.host;
    final handle = await guardPlatformCall(
      () => host.createSession(
        SessionConfigMessage(
          model: model.toMessage(),
          instructions: instructions,
          tools: [for (final tool in tools) tool.toMessage()],
          builtInTools: [for (final tool in builtInTools) tool.toMessage()],
          transcriptJson: transcript?.json,
          transcriptPolicy: transcriptErrorHandlingPolicy?._toMessage(),
        ),
      ),
    );
    return LanguageModelSession._(handle, {
      for (final tool in tools) tool.name: tool,
    });
  }

  final Map<String, Tool> _tools;

  /// One request at a time: Foundation Models rejects overlapping requests,
  /// and on an iOS 27 device a second request traps inside the framework
  /// rather than throwing, so this is enforced before reaching the platform.
  bool _responding = false;

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    _checkIdle();
    _responding = true;
    try {
      return await body();
    } finally {
      _responding = false;
    }
  }

  void _checkIdle() {
    if (_responding) {
      throw const FoundationModelsException(
        FoundationModelsErrorCode.concurrentRequests,
        'This session is already responding. Await the previous response, '
        'cancel its stream, or use another session.',
      );
    }
  }

  @override
  Future<ToolOutput> runTool(String name, GeneratedContent arguments) {
    final tool = _tools[name];
    if (tool == null) {
      throw StateError('The model called unknown tool "$name".');
    }
    return tool.call(arguments);
  }

  /// Generates a text response to [prompt].
  ///
  /// [prompt] is a [String] or a [Prompt] (which can carry images).
  Future<ModelResponse<String>> respond(
    Object prompt, {
    GenerationOptions options = const GenerationOptions(),
    ContextOptions contextOptions = const ContextOptions(),
  }) async {
    final message = await _exclusive(
      () => guardPlatformCall(
        () => bindings.host.respond(
          _request(prompt, options, contextOptions, null),
        ),
      ),
    );
    return ModelResponse(
      content: message.text ?? '',
      entries: _entries(message),
      usage: Usage.fromMessage(message.usage),
    );
  }

  /// Generates content matching [schema] (guided generation).
  Future<ModelResponse<GeneratedContent>> respondWithSchema(
    Object prompt,
    GenerationSchema schema, {
    GenerationOptions options = const GenerationOptions(),
    ContextOptions contextOptions = const ContextOptions(),
  }) async {
    final message = await _exclusive(
      () => guardPlatformCall(
        () => bindings.host.respond(
          _request(prompt, options, contextOptions, schema),
        ),
      ),
    );
    return ModelResponse(
      content: GeneratedContent(
        message.contentJson ?? '{}',
        isComplete: message.isComplete,
      ),
      entries: _entries(message),
      usage: Usage.fromMessage(message.usage),
    );
  }

  /// Streams a text response, snapshot by snapshot.
  ///
  /// Each snapshot's content is cumulative. Cancelling the subscription
  /// cancels generation.
  Stream<ResponseSnapshot<String>> streamResponse(
    Object prompt, {
    GenerationOptions options = const GenerationOptions(),
    ContextOptions contextOptions = const ContextOptions(),
  }) => _stream(
    prompt,
    options,
    contextOptions,
    null,
    (snapshot, previous) => snapshot.text ?? '',
  );

  /// Streams content matching [schema].
  Stream<ResponseSnapshot<GeneratedContent>> streamResponseWithSchema(
    Object prompt,
    GenerationSchema schema, {
    GenerationOptions options = const GenerationOptions(),
    ContextOptions contextOptions = const ContextOptions(),
  }) => _stream(
    prompt,
    options,
    contextOptions,
    schema,
    (snapshot, previous) => GeneratedContent(
      snapshot.contentJson ?? '{}',
      isComplete: snapshot.isComplete,
    ),
  );

  Stream<ResponseSnapshot<T>> _stream<T>(
    Object prompt,
    GenerationOptions options,
    ContextOptions contextOptions,
    GenerationSchema? schema,
    T Function(StreamSnapshotMessage snapshot, T? previous) convert,
  ) {
    _checkIdle();
    final request = _request(prompt, options, contextOptions, schema);
    final controller = StreamController<ResponseSnapshot<T>>();
    final sink = _SnapshotSink<T>(
      controller,
      convert,
      () => _responding = false,
    );
    controller
      ..onListen = () async {
        _checkIdle();
        _responding = true;
        bindings.registerStream(request.requestId, sink);
        try {
          await guardPlatformCall(() => bindings.host.startStream(request));
        } on Object catch (error, stack) {
          _responding = false;
          bindings.unregisterStream(request.requestId);
          if (!controller.isClosed) {
            controller
              ..addError(error, stack)
              ..close();
          }
        }
      }
      ..onCancel = () async {
        _responding = false;
        bindings.unregisterStream(request.requestId);
        if (!isDisposed) {
          await guardPlatformCall(
            () => bindings.host.cancelRequest(request.requestId),
          );
        }
      };
    return controller.stream;
  }

  RespondRequestMessage _request(
    Object prompt,
    GenerationOptions options,
    ContextOptions contextOptions,
    GenerationSchema? schema,
  ) {
    final resolved = switch (prompt) {
      final Prompt value => value,
      final String text => Prompt(text),
      _ => throw ArgumentError.value(
        prompt,
        'prompt',
        'must be a String or a Prompt',
      ),
    };
    return RespondRequestMessage(
      sessionHandle: handle,
      requestId: bindings.nextRequestId(),
      prompt: resolved.toMessage(),
      options: options.toMessage(),
      contextOptions: contextOptions.toMessage(),
      schemaJson: schema?.toJsonString(),
    );
  }

  static List<TranscriptEntry> _entries(ResponseMessage message) => [
    for (final entry in message.entries) TranscriptEntry.fromMessage(entry),
  ];

  /// Warms the model up, optionally for a prompt the user is about to send.
  Future<void> prewarm({Object? promptPrefix}) {
    final prefix = switch (promptPrefix) {
      final Prompt value => value,
      final String text => Prompt(text),
      null => null,
      _ => throw ArgumentError.value(
        promptPrefix,
        'promptPrefix',
        'must be a String or a Prompt',
      ),
    };
    return guardPlatformCall(
      () => bindings.host.prewarm(handle, prefix?.toMessage()),
    );
  }

  /// Everything the session has seen and produced.
  Future<Transcript> get transcript async {
    final message = await guardPlatformCall(
      () => bindings.host.transcript(handle),
    );
    return Transcript.fromMessage(message);
  }

  /// Whether a request is in flight. A session handles one at a time.
  Future<bool> get isResponding =>
      guardPlatformCall(() => bindings.host.isResponding(handle));

  /// Tokens used by the session so far (zero before iOS 27 / macOS 27).
  Future<Usage> get usage async => Usage.fromMessage(
    await guardPlatformCall(() => bindings.host.sessionUsage(handle)),
  );

  /// Sets what happens to the transcript when a request fails. Needs
  /// iOS 27 / macOS 27.
  Future<void> setTranscriptErrorHandlingPolicy(
    TranscriptErrorHandlingPolicy? policy,
  ) => guardPlatformCall(
    () => bindings.host.setTranscriptPolicy(handle, policy?._toMessage()),
  );

  /// Records the user's feedback about the last response, returning a JSON
  /// attachment to include in a bug report (Apple's
  /// `logFeedbackAttachment`). Needs iOS 27 / macOS 27.
  Future<Uint8List> logFeedback({
    FeedbackSentiment? sentiment,
    List<FeedbackIssue> issues = const [],
    String? desiredResponseText,
  }) => guardPlatformCall(
    () => bindings.host.logFeedbackAttachment(handle, sentiment?._toMessage(), [
      for (final issue in issues)
        FeedbackIssueMessage(
          category: issue.category._toMessage(),
          explanation: issue.explanation,
        ),
    ], desiredResponseText),
  );

  @override
  void onDispose() => bindings.unregisterToolHost(handle);

  @override
  String toString() =>
      'LanguageModelSession(${isDisposed ? 'disposed' : handle})';
}

class _SnapshotSink<T> implements StreamSink {
  _SnapshotSink(this._controller, this._convert, this._onFinished);

  final StreamController<ResponseSnapshot<T>> _controller;
  final T Function(StreamSnapshotMessage snapshot, T? previous) _convert;
  final void Function() _onFinished;
  T? _previous;
  String _previousText = '';

  @override
  void onSnapshot(StreamSnapshotMessage snapshot) {
    if (_controller.isClosed) return;
    final content = _convert(snapshot, _previous);
    final text = snapshot.text ?? '';
    final delta = text.startsWith(_previousText)
        ? text.substring(_previousText.length)
        : text;
    _previous = content;
    _previousText = text;
    _controller.add(
      ResponseSnapshot<T>(
        content: content,
        delta: delta,
        isComplete: snapshot.isComplete,
        usage: Usage.fromMessage(snapshot.usage),
      ),
    );
  }

  @override
  void onDone(ResponseMessage response) {
    _onFinished();
    if (!_controller.isClosed) _controller.close();
  }

  @override
  void onError(ErrorMessage error) {
    _onFinished();
    if (_controller.isClosed) return;
    _controller
      ..addError(
        FoundationModelsException.fromPlatformException(
          PlatformException(
            code: error.code,
            message: error.message,
            details: error.details,
          ),
        ),
      )
      ..close();
  }
}

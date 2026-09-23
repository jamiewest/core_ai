import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_models/foundation_models.dart';
import 'package:foundation_models/testing.dart';

/// A fake Foundation Models host.
class FakeHost implements FoundationModelsHostApi {
  final List<SessionConfigMessage> sessions = [];
  final List<RespondRequestMessage> requests = [];
  final List<int> released = [];
  final List<int> cancelled = [];
  PlatformException? nextError;
  AvailabilityStatusMessage status = AvailabilityStatusMessage.available;
  int _nextHandle = 10;

  /// Set by tests to observe the callback API from the "native" side.
  late FoundationModelsCallbackApi callbacks;

  void _maybeThrow() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Future<AvailabilityMessage> availability(ModelConfigMessage model) async {
    _maybeThrow();
    return AvailabilityMessage(status: status);
  }

  @override
  Future<ModelInfoMessage> modelInfo(ModelConfigMessage model) async =>
      ModelInfoMessage(
        contextSize: 4096,
        variantName: 'Fake 1',
        capabilities: [CapabilityMessage.toolCalling, CapabilityMessage.vision],
        supportedLanguages: ['en-US', 'fr-FR'],
      );

  @override
  Future<bool> supportsLocale(
    ModelConfigMessage model,
    String? localeIdentifier,
  ) async => localeIdentifier == null || localeIdentifier.startsWith('en');

  @override
  Future<int> tokenCount(
    ModelConfigMessage model,
    TokenCountRequestMessage request,
  ) async =>
      (request.prompt?.text.length ?? 0) + (request.instructions?.length ?? 0);

  @override
  Future<int> createSession(SessionConfigMessage config) async {
    _maybeThrow();
    sessions.add(config);
    return _nextHandle++;
  }

  @override
  Future<ResponseMessage> respond(RespondRequestMessage request) async {
    _maybeThrow();
    requests.add(request);
    return ResponseMessage(
      text: request.schemaJson == null ? 'fake answer' : null,
      contentJson: request.schemaJson == null ? null : '{"answer":"yes"}',
      isComplete: true,
      entries: [
        TranscriptEntryMessage(
          id: 'p1',
          kind: TranscriptEntryKindMessage.prompt,
          segments: [
            SegmentMessage(
              id: 's1',
              kind: SegmentKindMessage.text,
              text: request.prompt.text,
            ),
          ],
          toolCalls: [],
          toolDefinitions: [],
        ),
      ],
      usage: UsageMessage(
        inputTokens: 7,
        cachedInputTokens: 0,
        outputTokens: 3,
        reasoningTokens: 0,
      ),
    );
  }

  @override
  Future<void> startStream(RespondRequestMessage request) async {
    requests.add(request);
    UsageMessage usage() => UsageMessage(
      inputTokens: 1,
      cachedInputTokens: 0,
      outputTokens: 1,
      reasoningTokens: 0,
    );
    callbacks
      ..onStreamSnapshot(
        StreamSnapshotMessage(
          requestId: request.requestId,
          text: 'Hello',
          isComplete: false,
          usage: usage(),
        ),
      )
      ..onStreamSnapshot(
        StreamSnapshotMessage(
          requestId: request.requestId,
          text: 'Hello world',
          isComplete: true,
          usage: usage(),
        ),
      )
      ..onStreamDone(
        request.requestId,
        ResponseMessage(
          text: 'Hello world',
          isComplete: true,
          entries: [],
          usage: usage(),
        ),
      );
  }

  @override
  Future<void> cancelRequest(int requestId) async => cancelled.add(requestId);

  @override
  Future<TranscriptMessage> transcript(int sessionHandle) async =>
      TranscriptMessage(
        entries: [
          TranscriptEntryMessage(
            id: 'i1',
            kind: TranscriptEntryKindMessage.instructions,
            segments: [
              SegmentMessage(
                id: 's',
                kind: SegmentKindMessage.text,
                text: 'be nice',
              ),
            ],
            toolCalls: [],
            toolDefinitions: [
              ToolDefinitionMessage(
                name: 'get_weather',
                toolDescription: 'weather',
                parametersJson: '{"type":"object","title":"W"}',
                includesSchemaInInstructions: true,
              ),
            ],
          ),
          TranscriptEntryMessage(
            id: 'tc',
            kind: TranscriptEntryKindMessage.toolCalls,
            segments: [],
            toolCalls: [
              ToolCallMessage(
                id: 'c1',
                toolName: 'get_weather',
                argumentsJson: '{"city":"Paris"}',
              ),
            ],
            toolDefinitions: [],
          ),
        ],
        json: '{"transcript":{"entries":[]}}',
      );

  @override
  Future<void> release(int handle) async => released.add(handle);

  @override
  Future<int> releaseAll() async => 0;

  @override
  Future<int> liveHandleCount() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeHost: ${invocation.memberName}');
}

class FakePlatform implements FoundationModelsPlatformApi {
  FakePlatform({this.supported = true, this.supports27 = true});

  final bool supported;
  final bool supports27;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isVersion27Supported() async => supports27;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlatform: ${invocation.memberName}');
}

void main() {
  late FakeHost host;
  late FoundationModelsBindings bindings;

  setUp(() {
    host = FakeHost();
    bindings = FoundationModelsBindings(
      host: host,
      platform: FakePlatform(),
      registerCallbacks: false,
    );
    FoundationModelsBindings.instance = bindings;
    host.callbacks = bindings.callbackHandler;
  });

  group('schemas', () {
    test('builds Apple-shaped JSON Schema', () {
      final schema = GenerationSchema(
        DynamicGenerationSchema.object(
          name: 'Person',
          description: 'A person',
          properties: [
            SchemaProperty(
              'name',
              DynamicGenerationSchema.string(),
              description: 'Full name',
            ),
            SchemaProperty(
              'age',
              DynamicGenerationSchema.integer(minimum: 0, maximum: 120),
            ),
            SchemaProperty(
              'mood',
              DynamicGenerationSchema.string(anyOf: ['happy', 'sad']),
            ),
            SchemaProperty(
              'tags',
              DynamicGenerationSchema.array(
                DynamicGenerationSchema.string(),
                minimumElements: 1,
                maximumElements: 3,
              ),
              isOptional: true,
            ),
          ],
        ),
      );
      final json = schema.json;
      expect(json['type'], 'object');
      expect(json['title'], 'Person');
      expect(json['description'], 'A person');
      expect(json['required'], ['name', 'age', 'mood']);
      expect(json['x-order'], ['name', 'age', 'mood', 'tags']);
      expect(json['additionalProperties'], false);
      final properties = json['properties']! as Map<String, Object?>;
      expect((properties['name']! as Map)['description'], 'Full name');
      expect((properties['age']! as Map)['minimum'], 0);
      expect((properties['mood']! as Map)['enum'], ['happy', 'sad']);
      expect((properties['tags']! as Map)['maxItems'], 3);
      expect(schema.name, 'Person');
    });

    test('lifts named schemas into definitions', () {
      final cat = DynamicGenerationSchema.object(
        name: 'Cat',
        properties: [
          SchemaProperty('meows', DynamicGenerationSchema.boolean()),
        ],
      );
      final dog = DynamicGenerationSchema.object(
        name: 'Dog',
        properties: [
          SchemaProperty('barks', DynamicGenerationSchema.boolean()),
        ],
      );
      final schema = GenerationSchema(
        DynamicGenerationSchema.object(
          name: 'Home',
          properties: [
            SchemaProperty(
              'pet',
              DynamicGenerationSchema.anyOf(name: 'Pet', choices: [cat, dog]),
            ),
            SchemaProperty(
              'owner',
              DynamicGenerationSchema.reference('Person'),
            ),
          ],
        ),
        dependencies: [
          DynamicGenerationSchema.object(
            name: 'Person',
            properties: [
              SchemaProperty('name', DynamicGenerationSchema.string()),
            ],
          ),
        ],
      );
      final defs = schema.json[r'$defs']! as Map<String, Object?>;
      expect(defs.keys, containsAll(['Cat', 'Dog', 'Pet', 'Person']));
      final properties = schema.json['properties']! as Map<String, Object?>;
      expect((properties['pet']! as Map)[r'$ref'], r'#/$defs/Pet');
      expect((properties['owner']! as Map)[r'$ref'], r'#/$defs/Person');
      final pet = defs['Pet']! as Map<String, Object?>;
      expect((pet['anyOf']! as List).first, {r'$ref': r'#/$defs/Cat'});
    });

    test('normalizes a hand-written JSON schema', () {
      final schema = GenerationSchema.fromJsonSchema(const {
        'type': 'object',
        'title': 'Answer',
        'properties': {
          'answer': {'type': 'string'},
          'confidence': {'type': 'number'},
        },
      });
      expect(schema.json['x-order'], ['answer', 'confidence']);
      expect(schema.json['required'], ['answer', 'confidence']);
      expect(schema.json['additionalProperties'], false);
      expect(jsonDecode(schema.toJsonString()), schema.json);
    });
  });

  group('models', () {
    test('describes availability and info', () async {
      expect(
        (await SystemLanguageModel.defaultModel.availability()).isAvailable,
        isTrue,
      );
      host.status = AvailabilityStatusMessage.appleIntelligenceNotEnabled;
      final availability = await SystemLanguageModel.defaultModel
          .availability();
      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        ModelUnavailableReason.appleIntelligenceNotEnabled,
      );

      final info = await SystemLanguageModel.defaultModel.info();
      expect(info.contextSize, 4096);
      expect(info.variantName, 'Fake 1');
      expect(info.capabilities, contains(ModelCapability.vision));
      expect(info.supportedLanguages, contains('fr-FR'));
      expect(
        await SystemLanguageModel.defaultModel.supportsLocale('en-GB'),
        isTrue,
      );
      expect(
        await SystemLanguageModel.defaultModel.supportsLocale('de-DE'),
        isFalse,
      );
    });

    test('reports unsupported platforms without calling the host', () async {
      FoundationModelsBindings.instance = FoundationModelsBindings(
        host: host,
        platform: FakePlatform(supported: false),
        registerCallbacks: false,
      );
      final availability = await SystemLanguageModel.defaultModel
          .availability();
      expect(availability.isAvailable, isFalse);
      expect(availability.reason, ModelUnavailableReason.frameworkUnavailable);
      expect(await FoundationModels.isSupported(), isFalse);
    });

    test('counts tokens', () async {
      final count = await SystemLanguageModel.defaultModel.tokenCount(
        prompt: const Prompt('12345'),
        instructions: 'abc',
      );
      expect(count, 8);
    });

    test('maps model configuration', () {
      const model = SystemLanguageModel(
        useCase: ModelUseCase.contentTagging,
        guardrails: Guardrails.permissiveContentTransformations,
      );
      final message = model.toMessage();
      expect(message.kind, ModelKindMessage.system);
      expect(message.useCase, UseCaseMessage.contentTagging);
      expect(
        message.guardrails,
        GuardrailsMessage.permissiveContentTransformations,
      );
      expect(
        const PrivateCloudComputeLanguageModel().toMessage().kind,
        ModelKindMessage.privateCloudCompute,
      );
    });
  });

  group('sessions', () {
    test('passes instructions, tools and options', () async {
      final tool = FunctionTool(
        name: 'get_weather',
        description: 'weather',
        parameters: GenerationSchema(
          DynamicGenerationSchema.object(
            name: 'Args',
            properties: [
              SchemaProperty('city', DynamicGenerationSchema.string()),
            ],
          ),
        ),
        handler: (_) async => const ToolOutput.text('sunny'),
      );
      final session = await LanguageModelSession.create(
        instructions: 'be nice',
        tools: [tool],
        builtInTools: [BuiltInTool.ocr],
      );
      final config = host.sessions.single;
      expect(config.instructions, 'be nice');
      expect(config.tools.single.name, 'get_weather');
      expect(config.builtInTools, [BuiltInToolMessage.ocr]);

      final response = await session.respond(
        'hi',
        options: const GenerationOptions(
          temperature: 0.5,
          maximumResponseTokens: 20,
          sampling: SamplingMode.topK(10, seed: 3),
          toolCallingMode: ToolCallingMode.required,
        ),
        contextOptions: const ContextOptions(
          reasoningLevel: ReasoningLevel.deep,
        ),
      );
      expect(response.content, 'fake answer');
      expect(response.usage.inputTokens, 7);
      expect(response.entries.single.text, 'hi');

      final request = host.requests.single;
      expect(request.options.temperature, 0.5);
      expect(request.options.topK, 10);
      expect(request.options.seed, 3);
      expect(request.options.toolCallingMode, ToolCallingModeMessage.required);
      expect(request.contextOptions.reasoningLevel, ReasoningLevelMessage.deep);
      expect(request.schemaJson, isNull);
      await session.dispose();
    });

    test('sends prompts with images', () async {
      final session = await LanguageModelSession.create();
      await session.respond(
        Prompt(
          'What is this?',
          images: [
            ImageAttachment(
              const ImageInput.file('/tmp/a.png'),
              label: 'photo',
            ),
          ],
        ),
      );
      final prompt = host.requests.single.prompt;
      expect(prompt.text, 'What is this?');
      expect(prompt.images.single.label, 'photo');
      expect(prompt.images.single.image.kind, ImageInputKindMessage.file);
      expect(prompt.images.single.image.path, '/tmp/a.png');
      await session.dispose();
    });

    test('requests structured content', () async {
      final session = await LanguageModelSession.create();
      final schema = GenerationSchema(
        DynamicGenerationSchema.object(
          name: 'A',
          properties: [
            SchemaProperty('answer', DynamicGenerationSchema.string()),
          ],
        ),
      );
      final response = await session.respondWithSchema('q', schema);
      expect(host.requests.single.schemaJson, schema.toJsonString());
      expect(response.content['answer'], 'yes');
      expect(response.content.asMap, {'answer': 'yes'});
      expect(response.content.isComplete, isTrue);
      await session.dispose();
    });

    test('rejects a bad prompt type', () async {
      final session = await LanguageModelSession.create();
      expect(() => session.respond(42), throwsArgumentError);
      await session.dispose();
    });

    test('reads the transcript', () async {
      final session = await LanguageModelSession.create();
      final transcript = await session.transcript;
      expect(transcript.entries, hasLength(2));
      final instructions = transcript.entries.first as InstructionsEntry;
      expect(instructions.text, 'be nice');
      expect(instructions.tools.single.name, 'get_weather');
      final calls = transcript.entries.last as ToolCallsEntry;
      expect(calls.calls.single.toolName, 'get_weather');
      expect(calls.calls.single.arguments['city'], 'Paris');
      await session.dispose();
    });

    test('disposes once and rejects later use', () async {
      final session = await LanguageModelSession.create();
      final handle = session.handle;
      await session.dispose();
      await session.dispose();
      expect(host.released, [handle]);
      expect(() => session.respond('hi'), throwsStateError);
    });
  });

  group('streaming', () {
    test('emits cumulative snapshots with deltas', () async {
      final session = await LanguageModelSession.create();
      final snapshots = await session.streamResponse('hi').toList();
      expect(snapshots.map((s) => s.content), ['Hello', 'Hello world']);
      expect(snapshots.map((s) => s.delta), ['Hello', ' world']);
      expect(snapshots.last.isComplete, isTrue);
      await session.dispose();
    });

    test('cancels the native request', () async {
      final session = await LanguageModelSession.create();
      final subscription = session.streamResponse('hi').listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(host.cancelled, hasLength(1));
      await session.dispose();
    });
  });

  group('tools', () {
    test('routes a tool call to the Dart handler', () async {
      GeneratedContent? seen;
      final tool = FunctionTool(
        name: 'get_weather',
        description: 'weather',
        parameters: GenerationSchema(
          DynamicGenerationSchema.object(
            name: 'Args',
            properties: [
              SchemaProperty('city', DynamicGenerationSchema.string()),
            ],
          ),
        ),
        handler: (arguments) async {
          seen = arguments;
          return const ToolOutput.json({'temperature': 21});
        },
      );
      final session = await LanguageModelSession.create(tools: [tool]);
      final result = await host.callbacks.callTool(
        ToolCallRequestMessage(
          sessionHandle: session.handle,
          toolName: 'get_weather',
          argumentsJson: '{"city":"Paris"}',
        ),
      );
      expect(seen!['city'], 'Paris');
      expect(result.contentJson, '{"temperature":21}');

      await expectLater(
        host.callbacks.callTool(
          ToolCallRequestMessage(
            sessionHandle: session.handle,
            toolName: 'nope',
            argumentsJson: '{}',
          ),
        ),
        throwsStateError,
      );
      await session.dispose();
    });

    test('stops routing to a disposed session', () async {
      final session = await LanguageModelSession.create(
        tools: [
          FunctionTool(
            name: 't',
            description: 'd',
            parameters: GenerationSchema(
              DynamicGenerationSchema.object(name: 'A', properties: const []),
            ),
            handler: (_) async => const ToolOutput.text('x'),
          ),
        ],
      );
      final handle = session.handle;
      await session.dispose();
      await expectLater(
        host.callbacks.callTool(
          ToolCallRequestMessage(
            sessionHandle: handle,
            toolName: 't',
            argumentsJson: '{}',
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('errors', () {
    test('maps platform errors with details', () async {
      host.nextError = PlatformException(
        code: 'context_window_exceeded',
        message: 'too long',
        details: '{"contextSize":4096,"tokenCount":5000}',
      );
      await expectLater(
        LanguageModelSession.create(),
        throwsA(
          isA<FoundationModelsException>()
              .having(
                (e) => e.code,
                'code',
                FoundationModelsErrorCode.contextWindowExceeded,
              )
              .having((e) => e.contextSize, 'contextSize', 4096)
              .having((e) => e.tokenCount, 'tokenCount', 5000),
        ),
      );

      host.nextError = PlatformException(code: 'channel-error');
      await expectLater(
        LanguageModelSession.create(),
        throwsA(
          isA<FoundationModelsException>().having(
            (e) => e.code,
            'code',
            FoundationModelsErrorCode.unsupported,
          ),
        ),
      );

      host.nextError = PlatformException(
        code: 'rate_limited',
        message: 'slow down',
        details: '{"resetDateMillis":1000}',
      );
      await expectLater(
        LanguageModelSession.create(),
        throwsA(
          isA<FoundationModelsException>().having(
            (e) => e.resetDate,
            'resetDate',
            DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        ),
      );

      host.nextError = PlatformException(code: 'brand_new_code');
      await expectLater(
        LanguageModelSession.create(),
        throwsA(
          isA<FoundationModelsException>().having(
            (e) => e.code,
            'code',
            FoundationModelsErrorCode.unknown,
          ),
        ),
      );
    });
  });

  group('content', () {
    test('decodes JSON and survives partial JSON', () {
      const content = GeneratedContent.new;
      final complete = content('{"a":1,"b":[2,3]}');
      expect(complete.asMap['a'], 1);
      expect(complete['b'], [2, 3]);
      expect(complete.isComplete, isTrue);

      final partial = content('{"a":', isComplete: false);
      expect(partial.value, isNull);
      expect(partial['a'], isNull);
      expect(partial.isComplete, isFalse);
      expect(() => partial.asMap, throwsStateError);
      expect(() => complete.asList, throwsStateError);
    });
  });
}

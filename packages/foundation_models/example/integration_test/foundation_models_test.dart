// End-to-end tests against the real Foundation Models framework. Run on
// macOS 27 (or an iOS 27 device) with Apple Intelligence enabled:
//
//   cd example && flutter test integration_test/foundation_models_test.dart -d macos
//
// Language-model output is not deterministic, so these assert structure and
// constraints, plus the parts this package controls (tool calls, schemas,
// cancellation, errors).

import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_models/foundation_models.dart';
import 'package:integration_test/integration_test.dart';

const model = SystemLanguageModel.defaultModel;
const timeout = Timeout(Duration(minutes: 2));

Matcher throwsFoundationModels(FoundationModelsErrorCode code) => throwsA(
  isA<FoundationModelsException>().having((e) => e.code, 'code', code),
);

/// A tool that records how the model called it.
final class RecordingTool extends Tool {
  RecordingTool({this.fails = false});

  final bool fails;
  final List<GeneratedContent> calls = [];

  @override
  String get name => 'get_weather';

  @override
  String get description =>
      'Gets the current weather for a city. Always use this tool when the '
      'user asks about weather.';

  @override
  GenerationSchema get parameters => GenerationSchema(
    DynamicGenerationSchema.object(
      name: 'WeatherArguments',
      properties: [
        SchemaProperty(
          'city',
          DynamicGenerationSchema.string(),
          description: 'The city to look up.',
        ),
      ],
    ),
  );

  @override
  Future<ToolOutput> call(GeneratedContent arguments) async {
    calls.add(arguments);
    if (fails) throw StateError('the weather service is down');
    return const ToolOutput.text('It is 21 degrees and sunny.');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(await FoundationModels.isSupported(), isTrue);
    expect(
      (await model.availability()).isAvailable,
      isTrue,
      reason: 'needs Apple Intelligence enabled',
    );
    await FoundationModels.releaseAll();
  });

  tearDown(() async {
    final live = await FoundationModels.liveHandleCount();
    // Clean up even when a test failed before disposing, so one failure does
    // not cascade into every later leak check.
    await FoundationModels.releaseAll();
    expect(live, 0, reason: 'a test leaked handles');
  });

  group('model', () {
    testWidgets('reports availability, info and languages', (_) async {
      final availability = await model.availability();
      expect(availability.isAvailable, isTrue);
      expect(availability.reason, isNull);

      final info = await model.info();
      expect(info.contextSize, greaterThan(0));
      expect(info.supportedLanguages, isNotEmpty);
      expect(await model.supportsLocale('en-US'), isTrue);

      if (await FoundationModels.isVersion27Supported()) {
        expect(info.variantName, isNotEmpty);
        expect(info.capabilities, contains(ModelCapability.toolCalling));
      }
    }, timeout: timeout);

    testWidgets('counts tokens', (_) async {
      final short = await model.tokenCount(prompt: const Prompt('Hello.'));
      final long = await model.tokenCount(
        prompt: const Prompt('Hello, this is a considerably longer prompt.'),
        instructions: 'You are a helpful assistant.',
      );
      expect(short, greaterThan(0));
      expect(long, greaterThan(short));
    }, timeout: timeout);

    testWidgets('reports Private Cloud Compute availability', (_) async {
      if (!await FoundationModels.isVersion27Supported()) return;
      const cloud = PrivateCloudComputeLanguageModel();
      final availability = await cloud.availability();
      expect(availability, isNotNull);
      if (availability.isAvailable) {
        final quota = await cloud.quotaUsage();
        expect(quota.isLimitReached, isFalse);
        final info = await cloud.info();
        expect(info.contextSize, greaterThan(0));
        expect(info.capabilities, contains(ModelCapability.reasoning));
      }
    }, timeout: timeout);
  });

  group('responses', () {
    testWidgets('answers a prompt and records the transcript', (_) async {
      final session = await LanguageModelSession.create(
        instructions: 'Answer with a single short sentence.',
      );
      final response = await session.respond('What is the capital of France?');
      expect(response.content.toLowerCase(), contains('paris'));
      expect(response.entries, isNotEmpty);

      final transcript = await session.transcript;
      expect(transcript.entries.first, isA<InstructionsEntry>());
      expect(transcript.entries.whereType<PromptEntry>(), hasLength(1));
      expect(transcript.entries.whereType<ResponseEntry>(), hasLength(1));
      expect(transcript.json, contains('capital of France'));
      expect(await session.isResponding, isFalse);

      if (await FoundationModels.isVersion27Supported()) {
        expect(response.usage.outputTokens, greaterThan(0));
        expect((await session.usage).totalTokens, greaterThan(0));
      }
      await session.dispose();
    }, timeout: timeout);

    testWidgets('respects maximumResponseTokens', (_) async {
      final session = await LanguageModelSession.create();
      final response = await session.respond(
        'Write a paragraph about the ocean.',
        options: const GenerationOptions(maximumResponseTokens: 16),
      );
      expect(response.content, isNotEmpty);
      if (await FoundationModels.isVersion27Supported()) {
        // The cap is approximate: the model finishes the token it started.
        // Without it this prompt produces well over a hundred tokens.
        expect(response.usage.outputTokens, lessThan(64));
      }
      await session.dispose();
    }, timeout: timeout);

    testWidgets('prewarms and rejects concurrent requests', (_) async {
      final session = await LanguageModelSession.create();
      await session.prewarm(promptPrefix: 'Tell me about');
      // The in-flight request may itself fail once a second one arrives, so
      // only the rejection of the second request is asserted.
      final first = session
          .respond('Tell me about the moon in one sentence.')
          .then<void>((_) {}, onError: (Object _) {});
      await expectLater(
        session.respond('And the sun?'),
        throwsFoundationModels(FoundationModelsErrorCode.concurrentRequests),
      );
      await first;
      await session.dispose();
    }, timeout: timeout);

    testWidgets('resumes from a saved transcript', (_) async {
      final first = await LanguageModelSession.create(
        instructions: 'Answer with a single short sentence.',
      );
      await first.respond('My favourite colour is blue. Remember it.');
      final saved = (await first.transcript).json;
      await first.dispose();

      final resumed = await LanguageModelSession.create(
        transcript: Transcript.fromJson(saved),
      );
      final response = await resumed.respond(
        'What is my favourite colour? Answer with one word.',
      );
      expect(response.content.toLowerCase(), contains('blue'));

      final decoded = await FoundationModels.decodeTranscript(saved);
      expect(decoded.entries, isNotEmpty);
      expect(decoded.entries.first, isA<InstructionsEntry>());
      await resumed.dispose();
    }, timeout: timeout);
  });

  group('guided generation', () {
    final schema = GenerationSchema(
      DynamicGenerationSchema.object(
        name: 'Movie',
        description: 'A movie recommendation.',
        properties: [
          SchemaProperty('title', DynamicGenerationSchema.string()),
          SchemaProperty(
            'year',
            DynamicGenerationSchema.integer(minimum: 1980, maximum: 2000),
          ),
          SchemaProperty(
            'mood',
            DynamicGenerationSchema.string(anyOf: ['happy', 'sad', 'tense']),
          ),
          SchemaProperty(
            'tags',
            DynamicGenerationSchema.array(
              DynamicGenerationSchema.string(),
              minimumElements: 2,
              maximumElements: 3,
            ),
          ),
        ],
      ),
    );

    testWidgets('produces content matching the schema', (_) async {
      final session = await LanguageModelSession.create();
      final response = await session.respondWithSchema(
        'Recommend a film from the 1990s.',
        schema,
      );
      final movie = response.content.asMap;
      expect(movie['title'], isA<String>());
      expect(
        movie['year'],
        allOf(isA<int>(), greaterThanOrEqualTo(1980), lessThanOrEqualTo(2000)),
      );
      expect(movie['mood'], isIn(['happy', 'sad', 'tense']));
      expect(
        movie['tags'],
        allOf(isA<List<Object?>>(), hasLength(inInclusiveRange(2, 3))),
      );
      expect(response.content.isComplete, isTrue);
      await session.dispose();
    }, timeout: timeout);

    testWidgets('validates schemas', (_) async {
      final canonical = await FoundationModels.validateSchema(schema);
      expect(canonical, contains('"title":"Movie"'));
      expect(canonical, contains('x-order'));

      final broken = GenerationSchema(
        DynamicGenerationSchema.object(
          name: 'Broken',
          properties: [
            SchemaProperty('other', DynamicGenerationSchema.reference('Nope')),
          ],
        ),
      );
      await expectLater(
        FoundationModels.validateSchema(broken),
        throwsFoundationModels(FoundationModelsErrorCode.schemaError),
      );
    }, timeout: timeout);

    testWidgets('accepts a hand-written JSON schema', (_) async {
      final schema = GenerationSchema.fromJsonSchema(const {
        'type': 'object',
        'title': 'Answer',
        'properties': {
          'answer': {
            'type': 'string',
            'enum': ['yes', 'no'],
          },
        },
      });
      final session = await LanguageModelSession.create();
      final response = await session.respondWithSchema(
        'Is the Pacific the largest ocean?',
        schema,
      );
      expect(response.content['answer'], isIn(['yes', 'no']));
      await session.dispose();
    }, timeout: timeout);
  });

  group('streaming', () {
    testWidgets('streams cumulative snapshots', (_) async {
      final session = await LanguageModelSession.create(
        instructions: 'Answer with two short sentences.',
      );
      final snapshots = <ResponseSnapshot<String>>[];
      await for (final snapshot in session.streamResponse(
        'Describe the sea.',
      )) {
        snapshots.add(snapshot);
      }
      expect(snapshots, isNotEmpty);
      expect(snapshots.last.content, isNotEmpty);
      for (var i = 1; i < snapshots.length; i++) {
        expect(
          snapshots[i].content.length,
          greaterThanOrEqualTo(snapshots[i - 1].content.length),
          reason: 'snapshots are cumulative',
        );
      }
      expect(snapshots.map((s) => s.delta).join(), snapshots.last.content);
      await session.dispose();
    }, timeout: timeout);

    testWidgets('streams structured content', (_) async {
      final schema = GenerationSchema(
        DynamicGenerationSchema.object(
          name: 'City',
          properties: [
            SchemaProperty('name', DynamicGenerationSchema.string()),
            SchemaProperty('country', DynamicGenerationSchema.string()),
          ],
        ),
      );
      final session = await LanguageModelSession.create();
      final snapshots = <ResponseSnapshot<GeneratedContent>>[];
      await for (final snapshot in session.streamResponseWithSchema(
        'Name a city in Japan.',
        schema,
      )) {
        snapshots.add(snapshot);
      }
      expect(snapshots, isNotEmpty);
      expect(snapshots.last.content.asMap['name'], isA<String>());
      await session.dispose();
    }, timeout: timeout);

    testWidgets('cancels a stream', (_) async {
      final session = await LanguageModelSession.create();
      final received = <String>[];
      final subscription = session
          .streamResponse('Write a long story about a lighthouse.')
          .listen((snapshot) => received.add(snapshot.content));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await subscription.cancel();
      final countAtCancel = received.length;
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(received.length, countAtCancel, reason: 'no events after cancel');

      // The session is usable again once the cancelled request settles.
      final response = await session.respond('Say OK.');
      expect(response.content, isNotEmpty);
      await session.dispose();
    }, timeout: timeout);
  });

  group('tools', () {
    testWidgets('the model calls a Dart tool', (_) async {
      final tool = RecordingTool();
      final session = await LanguageModelSession.create(
        instructions: 'Use the provided tools to answer questions.',
        tools: [tool],
      );
      final response = await session.respond(
        'What is the weather in Paris right now?',
      );
      expect(tool.calls, hasLength(1));
      expect(
        tool.calls.single['city'].toString().toLowerCase(),
        contains('paris'),
      );
      expect(response.content, contains('21'));

      final transcript = await session.transcript;
      expect(transcript.entries.whereType<ToolCallsEntry>(), isNotEmpty);
      expect(transcript.entries.whereType<ToolOutputEntry>(), isNotEmpty);
      expect(
        (transcript.entries.first as InstructionsEntry).tools.single.name,
        'get_weather',
      );
      await session.dispose();
    }, timeout: timeout);

    testWidgets('a failing tool surfaces as a tool error', (_) async {
      final tool = RecordingTool(fails: true);
      final session = await LanguageModelSession.create(
        instructions: 'Use the provided tools to answer questions.',
        tools: [tool],
      );
      await expectLater(
        session.respond('What is the weather in Berlin?'),
        throwsFoundationModels(FoundationModelsErrorCode.toolCallFailed),
      );
      expect(tool.calls, hasLength(1));
      await session.dispose();
    }, timeout: timeout);
  });

  group('errors and housekeeping', () {
    testWidgets('rejects a disposed session', (_) async {
      final session = await LanguageModelSession.create();
      await session.dispose();
      expect(() => session.respond('Hello?'), throwsStateError);
    }, timeout: timeout);

    testWidgets('reports a missing adapter file', (_) async {
      await expectLater(
        ModelAdapter.fromFile('/nonexistent/adapter.fmadapter'),
        throwsFoundationModels(FoundationModelsErrorCode.notFound),
      );
    }, timeout: timeout);

    testWidgets('logs feedback', (_) async {
      if (!await FoundationModels.isVersion27Supported()) return;
      final session = await LanguageModelSession.create();
      await session.respond('Say hello.');
      final attachment = await session.logFeedback(
        sentiment: FeedbackSentiment.negative,
        issues: const [
          FeedbackIssue(
            FeedbackIssueCategory.tooVerbose,
            explanation: 'too long',
          ),
        ],
        desiredResponseText: 'Hello.',
      );
      expect(attachment, isNotEmpty);
      await session.dispose();
    }, timeout: timeout);
  });
}

// End-to-end tests against the real Translation framework:
//
//   cd example && flutter test integration_test/apple_translation_test.dart -d macos
//
// Translation tests need the language pair downloaded on this device. When a
// pair is not installed the test is marked skipped, never passed.

import 'dart:async';

import 'package:apple_translation/apple_translation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Matcher throwsTranslation(TranslationErrorCode code) =>
    throwsA(isA<TranslationException>().having((e) => e.code, 'code', code));

const availability = LanguageAvailability();

/// Whether [from] → [to] can be translated right now. Marks the test skipped
/// when it cannot.
Future<bool> requireInstalled(String from, String? to) async {
  final status = await availability.status(from: from, to: to);
  if (status == LanguageStatus.installed) return true;
  markTestSkipped(
    '$from -> ${to ?? 'system-selected target'} is ${status.name} on this '
    'device, not installed. '
    'Download it in System Settings > General > Language & Region > '
    'Translation Languages to run this test.',
  );
  return false;
}

/// Runs [body] with a session that is disposed afterwards.
Future<void> withSession(
  String source,
  String? target,
  Future<void> Function(TranslationSession session) body, {
  TranslationStrategy? strategy,
}) async {
  final session = await TranslationSession.create(
    installedSource: source,
    target: target,
    preferredStrategy: strategy,
  );
  try {
    await body(session);
  } finally {
    await session.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(await Translation.isSupported(), isTrue);
    await Translation.releaseAll();
  });

  tearDown(() async {
    final live = await Translation.liveHandleCount();
    await Translation.releaseAll();
    expect(live, 0, reason: 'a test leaked handles');
  });

  group('platform', () {
    testWidgets('reports macOS 27 capabilities', (_) async {
      expect(await Translation.isInstalledSessionSupported(), isTrue);
      expect(await Translation.isStrategySupported(), isTrue);
      expect(
        await LanguageAvailability.defaultStrategy(),
        TranslationStrategy.highFidelity,
      );
    });
  });

  group('languages', () {
    testWidgets('lists supported languages, sorted', (_) async {
      final languages = await availability.supportedLanguages;
      final ids = languages.map((l) => l.identifier).toList();
      expect(ids, containsAll(['en', 'es', 'fr', 'de', 'ja', 'zh']));
      expect(ids, [...ids]..sort());
      final spanish = languages.firstWhere((l) => l.identifier == 'es');
      expect(spanish.languageCode, 'es');
      expect(spanish.maximalIdentifier, 'es-Latn-ES');
      expect(spanish.localizedName, isNotEmpty);
    });

    testWidgets('resolves and normalizes identifiers', (_) async {
      final zh = await Language.resolve('zh-Hans');
      expect(zh.identifier, 'zh');
      expect(zh.maximalIdentifier, 'zh-Hans-CN');
      expect(zh.script, 'Hans');
      expect(zh, await Language.resolve('zh'));

      final traditional = await Language.resolve('zh-Hant');
      expect(traditional.identifier, 'zh-TW');
      expect(traditional, isNot(zh));

      final english = await Language.resolve('EN_us');
      expect(english.identifier, 'en');
      expect(english.region, 'US');
      expect(english.maximalIdentifier, 'en-Latn-US');

      await expectLater(
        Language.resolve('  '),
        throwsTranslation(TranslationErrorCode.invalidArgument),
      );
    });
  });

  group('availability', () {
    testWidgets('reports a status for a pair', (_) async {
      expect(
        await availability.status(from: 'en', to: 'es'),
        isIn(LanguageStatus.values),
      );
      expect(
        await availability.status(from: 'en', to: 'en'),
        LanguageStatus.unsupported,
      );
      expect(
        await availability.status(from: 'en', to: 'tlh'),
        LanguageStatus.unsupported,
      );
    });

    testWidgets('reports a status for text', (_) async {
      expect(
        await availability.statusForText('Hello, how are you?', to: 'es'),
        isIn([LanguageStatus.installed, LanguageStatus.supported]),
      );
    });

    testWidgets('cannot identify empty text', (_) async {
      await expectLater(
        availability.statusForText('', to: 'es'),
        throwsTranslation(TranslationErrorCode.unableToIdentifyLanguage),
      );
    });

    testWidgets('rejects a blank language', (_) async {
      await expectLater(
        availability.status(from: '', to: 'es'),
        throwsTranslation(TranslationErrorCode.invalidArgument),
      );
    });
  });

  group('translation', () {
    testWidgets('translates English to Spanish', (_) async {
      if (!await requireInstalled('en', 'es')) return;
      await withSession('en', 'es', (session) async {
        expect(session.sourceLanguage?.identifier, 'en');
        expect(session.targetLanguage?.identifier, 'es');
        expect(session.canRequestDownloads, isFalse);
        expect(session.preferredStrategy, TranslationStrategy.highFidelity);
        expect(await session.isReady, isTrue);
        await session.prepareTranslation();

        final response = await session.translate('Hello, how are you?');
        expect(response.targetText, contains('Hola'));
        expect(response.sourceText, 'Hello, how are you?');
        expect(response.sourceLanguage.languageCode, 'en');
        expect(response.targetLanguage.identifier, 'es');
        expect(response.clientIdentifier, isNull);
        expect(response.targetSegments, isNull);
      });
    });

    testWidgets('translates into French and German', (_) async {
      if (!await requireInstalled('en', 'fr')) return;
      if (!await requireInstalled('en', 'de')) return;
      await withSession('en', 'fr', (session) async {
        expect(
          (await session.translate('Hello, how are you?')).targetText,
          contains('Bonjour'),
        );
      });
      await withSession('en', 'de', (session) async {
        expect(
          (await session.translate('Hello, how are you?')).targetText,
          contains('Hallo'),
        );
      });
    });

    testWidgets('translates a batch in request order', (_) async {
      if (!await requireInstalled('en', 'es')) return;
      await withSession('en', 'es', (session) async {
        final responses = await session.translations(const [
          TranslationRequest('Good morning', clientIdentifier: 'a'),
          TranslationRequest('Thank you', clientIdentifier: 'b'),
          TranslationRequest('', clientIdentifier: 'c'),
        ]);
        expect(responses.map((r) => r.clientIdentifier), ['a', 'b', 'c']);
        expect(responses[0].targetText, contains('Buenos días'));
        expect(responses[1].targetText, contains('Gracias'));
        // Unlike translate(''), an empty request in a batch does not throw.
        expect(responses[2].targetText, isEmpty);
      });
    });

    testWidgets('streams batch responses', (_) async {
      if (!await requireInstalled('en', 'es')) return;
      await withSession('en', 'es', (session) async {
        final responses = await session.translateBatch(const [
          TranslationRequest('Good night', clientIdentifier: 'x'),
          TranslationRequest('The cat is black.', clientIdentifier: 'y'),
        ]).toList();
        final byId = {for (final r in responses) r.clientIdentifier: r};
        expect(byId.keys, unorderedEquals(['x', 'y']));
        expect(byId['x']!.targetText, contains('noches'));
        expect(byId['y']!.targetText, contains('gato'));
      });
    });

    testWidgets('cancelling a batch stream keeps the session usable', (
      _,
    ) async {
      if (!await requireInstalled('en', 'es')) return;
      await withSession('en', 'es', (session) async {
        final first = Completer<TranslationResponse>();
        final subscription = session
            .translateBatch([
              for (var i = 0; i < 20; i++)
                TranslationRequest(
                  'This is sentence number $i.',
                  clientIdentifier: '$i',
                ),
            ])
            .listen((response) {
              if (!first.isCompleted) first.complete(response);
            });
        await first.future;
        await subscription.cancel();
        expect(
          (await session.translate('Thank you')).targetText,
          contains('Gracias'),
        );
      });
    });

    testWidgets('keeps segments that skip translation', (_) async {
      if (!await requireInstalled('en', 'es')) return;
      await withSession('en', 'es', (session) async {
        final response = await session.translateSegments(const [
          TextSegment('Hello '),
          TextSegment.skip('Acme Widget'),
          TextSegment(' is great.'),
        ]);
        expect(response.sourceText, 'Hello Acme Widget is great.');
        expect(response.targetText, contains('Acme Widget'));
        expect(response.targetText, contains('Hola'));
        final segments = response.targetSegments!;
        expect(segments, contains(const TextSegment.skip('Acme Widget')));
        expect(segments.map((s) => s.text).join(), response.targetText);
      });
    });

    testWidgets('lets the system pick the target', (_) async {
      if (!await requireInstalled('en', null)) return;
      await withSession('en', null, (session) async {
        expect(session.targetLanguage, isNull);
        final response = await session.translate('Hello, how are you?');
        // The system chooses the target; it is never the source.
        expect(response.targetLanguage.languageCode, isNot('en'));
        expect(response.targetText, isNot('Hello, how are you?'));
      });
    });

    testWidgets('translates with the low-latency strategy when installed', (
      _,
    ) async {
      const lowLatency = LanguageAvailability(
        preferredStrategy: TranslationStrategy.lowLatency,
      );
      final status = await lowLatency.status(from: 'en', to: 'es');
      await withSession('en', 'es', strategy: TranslationStrategy.lowLatency, (
        session,
      ) async {
        expect(session.preferredStrategy, TranslationStrategy.lowLatency);
        switch (status) {
          case LanguageStatus.installed:
            expect(
              (await session.translate('Hello, how are you?')).targetText,
              contains('Hola'),
            );
          case LanguageStatus.supported:
            // The low-latency model is downloaded separately.
            expect(await session.isReady, isFalse);
            await expectLater(
              session.translate('Hello, how are you?'),
              throwsTranslation(TranslationErrorCode.notInstalled),
            );
          case LanguageStatus.unsupported:
            markTestSkipped('en -> es low latency is unsupported here.');
        }
      });
    });
  });

  group('errors', () {
    testWidgets('empty text is nothing to translate', (_) async {
      if (!await requireInstalled('en', 'es')) return;
      await withSession('en', 'es', (session) async {
        await expectLater(
          session.translate(''),
          throwsTranslation(TranslationErrorCode.nothingToTranslate),
        );
        // Whitespace passes through unchanged.
        expect((await session.translate('   ')).targetText, '   ');
      });
    });

    testWidgets('an identical pair is unsupported', (_) async {
      await withSession('en', 'en', (session) async {
        expect(await session.isReady, isFalse);
        await expectLater(
          session.translate('Hello'),
          throwsA(
            isA<TranslationException>()
                .having(
                  (e) => e.code,
                  'code',
                  TranslationErrorCode.unsupportedLanguagePairing,
                )
                .having(
                  (e) => e.message,
                  'message',
                  'This language pairing is not supported.',
                ),
          ),
        );
      });
    });

    testWidgets('unknown languages are unsupported', (_) async {
      await withSession('tlh', 'es', (session) async {
        await expectLater(
          session.translate('Hello'),
          throwsTranslation(TranslationErrorCode.unsupportedSourceLanguage),
        );
      });
      await withSession('en', 'tlh', (session) async {
        await expectLater(
          session.translate('Hello'),
          throwsTranslation(TranslationErrorCode.unsupportedTargetLanguage),
        );
        await expectLater(
          session.prepareTranslation(),
          throwsTranslation(TranslationErrorCode.unsupportedTargetLanguage),
        );
      });
    });

    testWidgets('batch errors reach the stream', (_) async {
      await withSession('en', 'en', (session) async {
        await expectLater(
          session.translateBatch(const [TranslationRequest('Hello')]),
          emitsError(
            isA<TranslationException>().having(
              (e) => e.code,
              'code',
              TranslationErrorCode.unsupportedLanguagePairing,
            ),
          ),
        );
      });
    });

    testWidgets('a cancelled session stays cancelled', (_) async {
      await withSession('en', 'fr', (session) async {
        await session.cancel();
        await expectLater(
          session.translate('Hello'),
          throwsTranslation(TranslationErrorCode.alreadyCancelled),
        );
      });
    });

    testWidgets('a blank language is rejected', (_) async {
      await expectLater(
        TranslationSession.create(installedSource: ' ', target: 'es'),
        throwsTranslation(TranslationErrorCode.invalidArgument),
      );
    });
  });

  group('handles', () {
    testWidgets('dispose releases the native session', (_) async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      expect(await Translation.liveHandleCount(), 1);
      await session.dispose();
      expect(await Translation.liveHandleCount(), 0);
      expect(() => session.translate('Hello'), throwsStateError);
    });

    testWidgets('a released handle is invalid', (_) async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      expect(await Translation.releaseAll(), 1);
      await expectLater(
        session.translate('Hello'),
        throwsTranslation(TranslationErrorCode.invalidHandle),
      );
      await session.dispose();
    });
  });
}

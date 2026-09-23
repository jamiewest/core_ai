import 'dart:async';

import 'package:apple_translation/apple_translation.dart';
import 'package:apple_translation/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

LanguageMessage lang(String minimal, String maximal) => LanguageMessage(
  minimalIdentifier: minimal,
  maximalIdentifier: maximal,
  languageCode: minimal.split('-').first,
  script: maximal.split('-')[1],
  region: maximal.split('-').length > 2 ? maximal.split('-')[2] : null,
  localizedName: 'Name of $minimal',
);

final en = lang('en', 'en-Latn-US');
final es = lang('es', 'es-Latn-ES');

TranslationResponseMessage response(
  String source,
  String target, {
  String? clientIdentifier,
  List<TextSegmentMessage>? targetSegments,
}) => TranslationResponseMessage(
  sourceLanguage: en,
  targetLanguage: es,
  sourceText: source,
  targetText: target,
  targetSegments: targetSegments,
  clientIdentifier: clientIdentifier,
);

/// A fake Translation host that records calls.
class FakeHost implements AppleTranslationHostApi {
  final List<String> calls = [];
  final List<Object?> lastArguments = [];
  final List<int> released = [];
  final List<int> cancelledRequests = [];
  final List<int> cancelledSessions = [];
  PlatformException? nextError;
  int _nextHandle = 100;
  int live = 0;

  /// Called by [startBatch] after it returns, to simulate native events.
  void Function(int requestId, List<TranslationRequestMessage> requests)?
  onStartBatch;

  void _record(String name, List<Object?> arguments) {
    calls.add(name);
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    lastArguments
      ..clear()
      ..addAll(arguments);
  }

  @override
  Future<LanguageMessage> language(String identifier) async {
    _record('language', [identifier]);
    return lang('zh', 'zh-Hans-CN');
  }

  @override
  Future<List<LanguageMessage>> supportedLanguages(
    StrategyMessage? strategy,
  ) async {
    _record('supportedLanguages', [strategy]);
    return [en, es];
  }

  @override
  Future<LanguageStatusMessage> status(
    String source,
    String? target,
    StrategyMessage? strategy,
  ) async {
    _record('status', [source, target, strategy]);
    return LanguageStatusMessage.supported;
  }

  @override
  Future<LanguageStatusMessage> statusForText(
    String text,
    String? target,
    StrategyMessage? strategy,
  ) async {
    _record('statusForText', [text, target, strategy]);
    return LanguageStatusMessage.installed;
  }

  StrategyMessage? defaultStrategyResult = StrategyMessage.highFidelity;

  @override
  Future<StrategyMessage?> defaultStrategy() async {
    _record('defaultStrategy', []);
    return defaultStrategyResult;
  }

  @override
  Future<SessionInfoMessage> createSession(
    String source,
    String? target,
    StrategyMessage? strategy,
  ) async {
    _record('createSession', [source, target, strategy]);
    live++;
    return SessionInfoMessage(
      handle: _nextHandle++,
      sourceLanguage: en,
      targetLanguage: target == null ? null : es,
      canRequestDownloads: false,
      preferredStrategy: strategy ?? StrategyMessage.highFidelity,
    );
  }

  @override
  Future<bool> isReady(int handle) async {
    _record('isReady', [handle]);
    return true;
  }

  @override
  Future<TranslationResponseMessage> translate(
    int handle,
    TranslationRequestMessage request,
  ) async {
    _record('translate', [handle, request]);
    return response(
      request.sourceText,
      'Hola',
      targetSegments: request.segments == null
          ? null
          : [
              TextSegmentMessage(text: 'Hola, ', skipsTranslation: false),
              TextSegmentMessage(text: 'Acme', skipsTranslation: true),
            ],
    );
  }

  @override
  Future<List<TranslationResponseMessage>> translations(
    int handle,
    List<TranslationRequestMessage> requests,
  ) async {
    _record('translations', [handle, requests]);
    return [
      for (final request in requests)
        response(
          request.sourceText,
          '${request.sourceText} (es)',
          clientIdentifier: request.clientIdentifier,
        ),
    ];
  }

  @override
  Future<void> startBatch(
    int handle,
    int requestId,
    List<TranslationRequestMessage> requests,
  ) async {
    _record('startBatch', [handle, requestId, requests]);
    final callback = onStartBatch;
    if (callback != null) {
      scheduleMicrotask(() => callback(requestId, requests));
    }
  }

  @override
  Future<void> cancelRequest(int requestId) async {
    _record('cancelRequest', [requestId]);
    cancelledRequests.add(requestId);
  }

  @override
  Future<void> prepareTranslation(int handle) async {
    _record('prepareTranslation', [handle]);
  }

  @override
  Future<void> cancelSession(int handle) async {
    _record('cancelSession', [handle]);
    cancelledSessions.add(handle);
  }

  @override
  Future<void> release(int handle) async {
    _record('release', [handle]);
    released.add(handle);
    live--;
  }

  @override
  Future<int> releaseAll() async {
    _record('releaseAll', []);
    final count = live;
    live = 0;
    return count;
  }

  @override
  Future<int> liveHandleCount() async {
    _record('liveHandleCount', []);
    return live;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlatform implements AppleTranslationPlatformApi {
  FakePlatform({
    this.supported = true,
    this.sessions = true,
    this.strategies = true,
  });

  final bool supported;
  final bool sessions;
  final bool strategies;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isInstalledSessionSupported() async => sessions;

  @override
  Future<bool> isStrategySupported() async => strategies;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ThrowingPlatform extends FakePlatform {
  @override
  Future<bool> isSupported() async =>
      throw PlatformException(code: 'channel-error');
}

Matcher throwsTranslation(TranslationErrorCode code) =>
    throwsA(isA<TranslationException>().having((e) => e.code, 'code', code));

void main() {
  late FakeHost host;
  late TranslationBindings bindings;

  setUp(() {
    host = FakeHost();
    bindings = TranslationBindings(
      host: host,
      platform: FakePlatform(),
      registerCallbacks: false,
    );
    TranslationBindings.instance = bindings;
  });

  group('Translation', () {
    test('reports platform capabilities', () async {
      expect(await Translation.isSupported(), isTrue);
      expect(await Translation.isInstalledSessionSupported(), isTrue);
      expect(await Translation.isStrategySupported(), isTrue);

      TranslationBindings.instance = TranslationBindings(
        host: host,
        platform: FakePlatform(sessions: false, strategies: false),
        registerCallbacks: false,
      );
      expect(await Translation.isInstalledSessionSupported(), isFalse);
      expect(await Translation.isStrategySupported(), isFalse);
    });

    test('isSupported is false when the platform channel fails', () async {
      TranslationBindings.instance = TranslationBindings(
        host: host,
        platform: ThrowingPlatform(),
        registerCallbacks: false,
      );
      expect(await Translation.isSupported(), isFalse);
    });

    test('forwards handle housekeeping', () async {
      await TranslationSession.create(installedSource: 'en', target: 'es');
      expect(await Translation.liveHandleCount(), 1);
      expect(await Translation.releaseAll(), 1);
      expect(await Translation.liveHandleCount(), 0);
    });
  });

  group('Language', () {
    test('resolves identifiers through Locale.Language', () async {
      final language = await Language.resolve('zh-Hans');
      expect(host.lastArguments, ['zh-Hans']);
      expect(language.identifier, 'zh');
      expect(language.maximalIdentifier, 'zh-Hans-CN');
      expect(language.languageCode, 'zh');
      expect(language.script, 'Hans');
      expect(language.region, 'CN');
      expect(language.localizedName, 'Name of zh');
      expect(language.toString(), 'zh');
    });

    test('compares by maximal identifier', () {
      const zh = Language(identifier: 'zh', maximalIdentifier: 'zh-Hans-CN');
      const zhHans = Language(
        identifier: 'zh-Hans',
        maximalIdentifier: 'zh-Hans-CN',
      );
      const zhTw = Language(
        identifier: 'zh-TW',
        maximalIdentifier: 'zh-Hant-TW',
      );
      expect(zh, zhHans);
      expect(zh.hashCode, zhHans.hashCode);
      expect(zh, isNot(zhTw));
      expect({zh, zhHans, zhTw}, hasLength(2));
    });

    test('maps invalid identifiers to invalidArgument', () async {
      host.nextError = PlatformException(
        code: 'invalid_argument',
        message: 'A language identifier must not be empty.',
      );
      await expectLater(
        Language.resolve(' '),
        throwsTranslation(TranslationErrorCode.invalidArgument),
      );
    });
  });

  group('LanguageAvailability', () {
    test('lists supported languages', () async {
      final languages = await const LanguageAvailability().supportedLanguages;
      expect(languages.map((l) => l.identifier), ['en', 'es']);
      expect(host.lastArguments, [null]);
    });

    test('passes the strategy', () async {
      const availability = LanguageAvailability(
        preferredStrategy: TranslationStrategy.lowLatency,
      );
      await availability.supportedLanguages;
      expect(host.lastArguments, [StrategyMessage.lowLatency]);
      expect(
        await availability.status(from: 'en', to: 'es'),
        LanguageStatus.supported,
      );
      expect(host.lastArguments, ['en', 'es', StrategyMessage.lowLatency]);
    });

    test('checks status for a pair and for text', () async {
      const availability = LanguageAvailability();
      expect(
        await availability.status(from: 'en', to: 'es'),
        LanguageStatus.supported,
      );
      expect(host.lastArguments, ['en', 'es', null]);
      expect(await availability.status(from: 'en'), LanguageStatus.supported);
      expect(host.lastArguments, ['en', null, null]);

      expect(
        await availability.statusForText('Hello', to: 'fr'),
        LanguageStatus.installed,
      );
      expect(host.lastArguments, ['Hello', 'fr', null]);
    });

    test('maps every status', () {
      expect(
        LanguageStatusMessage.values.map(LanguageStatus.fromMessage),
        LanguageStatus.values,
      );
    });

    test('reports the default strategy', () async {
      expect(
        await LanguageAvailability.defaultStrategy(),
        TranslationStrategy.highFidelity,
      );
      host.defaultStrategyResult = null;
      expect(await LanguageAvailability.defaultStrategy(), isNull);
    });

    test('maps unableToIdentifyLanguage', () async {
      host.nextError = PlatformException(
        code: 'unable_to_identify_language',
        message: 'Unable to identify the language.',
      );
      await expectLater(
        const LanguageAvailability().statusForText(''),
        throwsTranslation(TranslationErrorCode.unableToIdentifyLanguage),
      );
    });
  });

  group('TranslationStrategy', () {
    test('round-trips through messages', () {
      for (final strategy in TranslationStrategy.values) {
        expect(TranslationStrategy.fromMessage(strategy.toMessage()), strategy);
      }
    });
  });

  group('errors', () {
    test('maps every wire code', () {
      for (final code in TranslationErrorCode.values) {
        final error = TranslationException.fromPlatformException(
          PlatformException(
            code: code.wireName,
            message: 'boom',
            details: 'why',
          ),
        );
        expect(error.code, code);
        expect(error.message, 'boom');
        expect(error.details, 'why');
      }
    });

    test('maps a missing host API to unsupported', () {
      final error = TranslationException.fromPlatformException(
        PlatformException(code: 'channel-error', message: 'no channel'),
      );
      expect(error.code, TranslationErrorCode.unsupported);
      expect(error.toString(), contains('unsupported'));
    });

    test('maps unrecognized codes to unknown', () {
      final error = TranslationException.fromPlatformException(
        PlatformException(code: 'brand_new'),
      );
      expect(error.code, TranslationErrorCode.unknown);
      expect(error.message, 'brand_new');
    });
  });

  group('TranslationSession', () {
    test('creates a session from installed languages', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
        preferredStrategy: TranslationStrategy.lowLatency,
      );
      expect(host.lastArguments, ['en', 'es', StrategyMessage.lowLatency]);
      expect(session.handle, 100);
      expect(session.sourceLanguage?.identifier, 'en');
      expect(session.targetLanguage?.identifier, 'es');
      expect(session.canRequestDownloads, isFalse);
      expect(session.preferredStrategy, TranslationStrategy.lowLatency);
      expect(await session.isReady, isTrue);
      await session.dispose();
    });

    test('allows a system-chosen target', () async {
      final session = await TranslationSession.create(installedSource: 'en');
      expect(host.lastArguments, ['en', null, null]);
      expect(session.targetLanguage, isNull);
      expect(session.toString(), contains('auto'));
      await session.dispose();
    });

    test('maps unsupported when sessions need a newer OS', () async {
      host.nextError = PlatformException(code: 'unsupported', message: 'old');
      await expectLater(
        TranslationSession.create(installedSource: 'en', target: 'es'),
        throwsTranslation(TranslationErrorCode.unsupported),
      );
    });

    test('translates text', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      final result = await session.translate('Hello');
      final request = host.lastArguments[1]! as TranslationRequestMessage;
      expect(host.lastArguments.first, session.handle);
      expect(request.sourceText, 'Hello');
      expect(request.segments, isNull);
      expect(result.targetText, 'Hola');
      expect(result.sourceText, 'Hello');
      expect(result.sourceLanguage.identifier, 'en');
      expect(result.targetLanguage.identifier, 'es');
      expect(result.targetSegments, isNull);
      expect(result.toString(), contains('en -> es'));
      await session.dispose();
    });

    test('translates segments that skip translation', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      final result = await session.translateSegments(const [
        TextSegment('Hello, '),
        TextSegment.skip('Acme'),
      ]);
      final request = host.lastArguments[1]! as TranslationRequestMessage;
      expect(request.sourceText, 'Hello, Acme');
      expect(request.segments!.map((s) => (s.text, s.skipsTranslation)), [
        ('Hello, ', false),
        ('Acme', true),
      ]);
      expect(result.targetSegments, const [
        TextSegment('Hola, '),
        TextSegment.skip('Acme'),
      ]);
      await session.dispose();
    });

    test('translates a batch in order with client identifiers', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      final results = await session.translations(const [
        TranslationRequest('Good morning', clientIdentifier: 'a'),
        TranslationRequest('Thank you', clientIdentifier: 'b'),
      ]);
      final requests =
          host.lastArguments[1]! as List<TranslationRequestMessage>;
      expect(requests.map((r) => r.clientIdentifier), ['a', 'b']);
      expect(results.map((r) => r.clientIdentifier), ['a', 'b']);
      expect(results.first.targetText, 'Good morning (es)');
      await session.dispose();
    });

    test('maps translation errors', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'en',
      );
      host.nextError = PlatformException(
        code: 'unsupported_language_pairing',
        message: 'This language pairing is not supported.',
        details: 'TranslationError(...)',
      );
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
              )
              .having((e) => e.details, 'details', 'TranslationError(...)'),
        ),
      );
      await session.dispose();
    });

    test('prepares and cancels', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      await session.prepareTranslation();
      expect(host.calls.last, 'prepareTranslation');
      await session.cancel();
      expect(host.cancelledSessions, [session.handle]);
      await session.dispose();
    });
  });

  group('batch streaming', () {
    late TranslationSession session;

    setUp(() async {
      session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
    });

    tearDown(() => session.dispose());

    test('streams responses until done', () async {
      host.onStartBatch = (requestId, requests) {
        for (final request in requests) {
          bindings.callbackHandler.onBatchResponse(
            requestId,
            response(
              request.sourceText,
              '${request.sourceText}!',
              clientIdentifier: request.clientIdentifier,
            ),
          );
        }
        bindings.callbackHandler.onBatchDone(requestId);
      };
      final results = await session.translateBatch(const [
        TranslationRequest('One', clientIdentifier: 'x'),
        TranslationRequest('Two', clientIdentifier: 'y'),
      ]).toList();
      expect(results.map((r) => (r.clientIdentifier, r.targetText)), [
        ('x', 'One!'),
        ('y', 'Two!'),
      ]);
      expect(bindings.activeBatchCount, 0);
      expect(host.cancelledRequests, isEmpty);
    });

    test('does not start until listened to', () async {
      final stream = session.translateBatch(const [TranslationRequest('Hi')]);
      await pumpEventQueue();
      expect(host.calls, isNot(contains('startBatch')));
      host.onStartBatch = (requestId, _) =>
          bindings.callbackHandler.onBatchDone(requestId);
      expect(await stream.toList(), isEmpty);
      expect(host.calls, contains('startBatch'));
    });

    test('surfaces native errors as TranslationException', () async {
      host.onStartBatch = (requestId, _) {
        bindings.callbackHandler.onBatchError(
          requestId,
          ErrorMessage(
            code: 'not_installed',
            message: 'Languages must be downloaded on-device.',
          ),
        );
      };
      await expectLater(
        session.translateBatch(const [TranslationRequest('Hi')]),
        emitsError(
          isA<TranslationException>().having(
            (e) => e.code,
            'code',
            TranslationErrorCode.notInstalled,
          ),
        ),
      );
      expect(bindings.activeBatchCount, 0);
    });

    test('surfaces errors from starting the batch', () async {
      host.nextError = PlatformException(code: 'invalid_handle');
      await expectLater(
        session.translateBatch(const [TranslationRequest('Hi')]),
        emitsError(
          isA<TranslationException>().having(
            (e) => e.code,
            'code',
            TranslationErrorCode.invalidHandle,
          ),
        ),
      );
      expect(bindings.activeBatchCount, 0);
    });

    test('cancelling the subscription cancels the native request', () async {
      final first = Completer<TranslationResponse>();
      host.onStartBatch = (requestId, _) => bindings.callbackHandler
          .onBatchResponse(requestId, response('One', 'Uno'));
      final subscription = session
          .translateBatch(const [
            TranslationRequest('One'),
            TranslationRequest('Two'),
          ])
          .listen(first.complete);
      expect((await first.future).targetText, 'Uno');
      final requestId = host.lastArguments[1]! as int;
      await subscription.cancel();
      expect(host.cancelledRequests, [requestId]);
      expect(bindings.activeBatchCount, 0);
      // Late events for the cancelled request are ignored.
      bindings.callbackHandler.onBatchResponse(
        requestId,
        response('Two', 'Dos'),
      );
      // The session itself is not cancelled.
      expect(host.cancelledSessions, isEmpty);
    });

    test('ignores events for unknown requests', () {
      bindings.callbackHandler.onBatchResponse(999, response('a', 'b'));
      bindings.callbackHandler.onBatchDone(999);
      bindings.callbackHandler.onBatchError(
        999,
        ErrorMessage(code: 'internal_error', message: 'x'),
      );
    });

    test('uses distinct request ids', () async {
      host.onStartBatch = (requestId, _) =>
          bindings.callbackHandler.onBatchDone(requestId);
      await session.translateBatch(const [TranslationRequest('a')]).toList();
      final firstId = host.lastArguments[1]! as int;
      await session.translateBatch(const [TranslationRequest('b')]).toList();
      expect(host.lastArguments[1], isNot(firstId));
    });
  });

  group('handle lifecycle', () {
    test('dispose releases once', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      final handle = session.handle;
      await session.dispose();
      await session.dispose();
      expect(host.released, [handle]);
      expect(session.isDisposed, isTrue);
      expect(session.toString(), contains('disposed'));
    });

    test('use after dispose throws StateError', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      await session.dispose();
      expect(() => session.handle, throwsStateError);
      expect(() => session.translate('Hi'), throwsStateError);
      expect(
        () => session.translateBatch(const [TranslationRequest('Hi')]),
        throwsStateError,
      );
      expect(host.calls.where((c) => c == 'translate'), isEmpty);
    });

    test('maps invalid handles from the platform', () async {
      final session = await TranslationSession.create(
        installedSource: 'en',
        target: 'es',
      );
      host.nextError = PlatformException(code: 'invalid_handle');
      await expectLater(
        session.isReady,
        throwsTranslation(TranslationErrorCode.invalidHandle),
      );
      await session.dispose();
    });
  });

  group('value types', () {
    test('TranslationRequest.segments joins the source text', () {
      final request = TranslationRequest.segments(const [
        TextSegment('Buy '),
        TextSegment.skip('Acme'),
      ], clientIdentifier: 'id');
      expect(request.sourceText, 'Buy Acme');
      expect(request.segments, hasLength(2));
      expect(() => request.segments!.add(const TextSegment('x')), throwsError);
      final message = request.toMessage();
      expect(message.clientIdentifier, 'id');
      expect(message.segments!.last.skipsTranslation, isTrue);
    });

    test('TextSegment equality and toString', () {
      expect(const TextSegment('a'), const TextSegment('a'));
      expect(const TextSegment('a'), isNot(const TextSegment.skip('a')));
      expect(const TextSegment.skip('a').toString(), 'TextSegment.skip(a)');
    });
  });
}

final Matcher throwsError = throwsA(isA<Error>());

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_playground/image_playground.dart';
import 'package:image_playground/testing.dart';

class FakePlatform extends ImagePlaygroundPlatformApi {
  bool missing = false;
  @override
  Future<bool> isSupported() async {
    if (missing) throw MissingPluginException();
    return true;
  }

  @override
  Future<CapabilitiesMessage> capabilities() async {
    if (missing) throw PlatformException(code: 'channel-error');
    return CapabilitiesMessage(
      isSupported: true,
      isAvailable: false,
      supportsStyles: true,
      supportsOptions: true,
      supportsVersion27Options: true,
      styles: [StyleMessage.animation, StyleMessage.illustration],
    );
  }
}

class FakeHost extends ImagePlaygroundHostApi {
  int next = 1;
  final sessions = <int, ConfigurationMessage>{};
  final released = <int>[];
  final cancelled = <int>[];
  final pending = <int, Completer<ResultMessage?>>{};
  Object? prepareError;
  Object? presentError;
  ResultMessage? output;
  bool wait = false;
  @override
  Future<int> prepare(ConfigurationMessage configuration) async {
    if (prepareError case final Object error) throw error;
    final handle = next++;
    sessions[handle] = configuration;
    return handle;
  }

  @override
  Future<ResultMessage?> present(int handle) async {
    if (presentError case final Object error) throw error;
    if (wait) return (pending[handle] = Completer<ResultMessage?>()).future;
    return output;
  }

  @override
  Future<SessionInfoMessage> info(int handle) async => SessionInfoMessage(
    conceptCount: sessions[handle]!.concepts.length,
    hasSourceImage: sessions[handle]!.sourceImage != null,
    allowedStyles: sessions[handle]!.allowedStyles ?? [],
    selectedStyle: sessions[handle]!.selectedStyle,
    isPresenting: pending.containsKey(handle),
  );
  @override
  Future<void> cancel(int handle) async {
    cancelled.add(handle);
    pending.remove(handle)?.complete(null);
  }

  @override
  Future<void> release(int handle) async {
    released.add(handle);
    sessions.remove(handle);
    pending.remove(handle)?.complete(null);
  }

  @override
  Future<int> releaseAll() async {
    final ids = sessions.keys.toList();
    for (final id in ids) {
      await release(id);
    }
    return ids.length;
  }

  @override
  Future<int> liveHandleCount() async => sessions.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImagePlaygroundBindings original;
  late FakePlatform platform;
  late FakeHost host;
  setUp(() {
    original = ImagePlaygroundBindings.instance;
    platform = FakePlatform();
    host = FakeHost();
    ImagePlaygroundBindings.instance = ImagePlaygroundBindings(
      platform: platform,
      host: host,
    );
  });
  tearDown(() {
    expect(host.sessions, isEmpty);
    ImagePlaygroundBindings.instance = original;
  });
  Matcher code(ImagePlaygroundErrorCode value) =>
      isA<ImagePlaygroundException>().having((e) => e.code, 'code', value);

  test(
    'capabilities distinguish OS support from device availability',
    () async {
      expect(await ImagePlayground.isSupported(), isTrue);
      final caps = await ImagePlayground.capabilities();
      expect(caps.isSupported, isTrue);
      expect(caps.isAvailable, isFalse);
      expect(caps.styles, [
        ImagePlaygroundStyle.animation,
        ImagePlaygroundStyle.illustration,
      ]);
      expect(() => caps.styles.clear(), throwsUnsupportedError);
    },
  );
  test('missing native channels report unsupported capabilities', () async {
    platform.missing = true;
    expect(await ImagePlayground.isSupported(), isFalse);
    expect((await ImagePlayground.capabilities()).isSupported, isFalse);
  });
  test(
    'concepts, input sources, styles and options cross the bridge',
    () async {
      final session = await ImagePlayground.prepare(
        concepts: [
          const ImagePlaygroundConcept.text('cat'),
          const ImagePlaygroundConcept.extracted(
            'A story about a cat',
            title: 'Story',
          ),
          const ImagePlaygroundConcept.image(ImageInput.file('/cat.png')),
          ImagePlaygroundConcept.drawing(Uint8List.fromList([1, 2])),
        ],
        sourceImage: ImageInput.pixels(
          width: 1,
          height: 1,
          bgra: Uint8List.fromList([0, 0, 255, 255]),
        ),
        allowedStyles: [ImagePlaygroundStyle.sketch],
        selectedStyle: ImagePlaygroundStyle.sketch,
        options: const ImagePlaygroundOptions(
          personalization: Personalization.disabled,
          variety: CreationVariety.low,
          strategy: CreationStrategy.editExisting,
          size: ImageSize(640, 480),
        ),
      );
      final message = host.sessions[session.handle]!;
      expect(message.concepts.map((c) => c.kind), ConceptKindMessage.values);
      expect(message.concepts[1].title, 'Story');
      expect(message.concepts[2].image?.path, '/cat.png');
      expect(message.sourceImage?.bytes, [0, 0, 255, 255]);
      expect(message.options?.personalization, PersonalizationMessage.disabled);
      expect(message.options?.strategy, StrategyMessage.editExisting);
      expect(message.options?.width, 640);
      expect((await session.info()).conceptCount, 4);
      expect((await session.info()).selectedStyle, ImagePlaygroundStyle.sketch);
      await session.dispose();
    },
  );
  test('binary inputs are copied and read-only', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final encoded = ImageInput.encoded(bytes) as EncodedImageInput;
    final drawing = ImagePlaygroundConcept.drawing(bytes) as DrawingConcept;
    final pixels =
        ImageInput.pixels(width: 1, height: 1, bgra: bytes) as PixelImageInput;
    bytes[0] = 9;
    expect(encoded.bytes.first, 1);
    expect(drawing.data.first, 1);
    expect(pixels.bgra.first, 1);
    expect(() => encoded.bytes[0] = 7, throwsUnsupportedError);
  });
  test(
    'null defaults preserve native option defaults and empty concepts',
    () async {
      final session = await ImagePlayground.prepare();
      final message = host.sessions[session.handle]!;
      expect(message.concepts, isEmpty);
      expect(message.allowedStyles, isNull);
      expect(message.options, isNull);
      await session.dispose();
    },
  );
  test(
    'successful image result is copied and convenience API releases session',
    () async {
      host.output = ResultMessage(
        bytes: Uint8List.fromList([1, 2, 3]),
        typeIdentifier: 'public.png',
        width: 512,
        height: 256,
      );
      final result = await ImagePlayground.present();
      host.output!.bytes[0] = 9;
      expect(result?.bytes, [1, 2, 3]);
      expect(result?.width, 512);
      expect(result?.isAdaptiveImageGlyph, isFalse);
      expect(host.released, [1]);
    },
  );
  test('adaptive glyph preserves content metadata and type', () async {
    host.output = ResultMessage(
      bytes: Uint8List.fromList([1]),
      typeIdentifier: 'com.apple.emoji.sticker',
      width: 128,
      height: 128,
      contentIdentifier: 'glyph-id',
      contentDescription: 'A happy cat',
    );
    final result = await ImagePlayground.present();
    expect(result?.isAdaptiveImageGlyph, isTrue);
    expect(result?.contentDescription, 'A happy cat');
    expect(result?.contentIdentifier, 'glyph-id');
  });
  test('user cancellation returns null and still disposes', () async {
    expect(await ImagePlayground.present(), isNull);
    expect(host.released, [1]);
  });
  test(
    'native presentation failure is typed and convenience API disposes',
    () async {
      host.presentError = PlatformException(
        code: 'unavailable',
        message: 'models missing',
      );
      await expectLater(
        ImagePlayground.present(),
        throwsA(code(ImagePlaygroundErrorCode.unavailable)),
      );
      expect(host.released, [1]);
    },
  );
  test('prepare errors are typed without creating a resource', () async {
    host.prepareError = PlatformException(code: 'invalid_argument');
    await expectLater(
      ImagePlayground.prepare(),
      throwsA(code(ImagePlaygroundErrorCode.invalidArgument)),
    );
    expect(host.released, isEmpty);
  });
  test('cancel closes an in-flight presentation exactly once', () async {
    host.wait = true;
    final session = await ImagePlayground.prepare();
    final showing = session.present();
    expect((await session.info()).isPresenting, isTrue);
    await Future.wait([session.cancel(), session.cancel()]);
    expect(await showing, isNull);
    expect(host.cancelled, [session.handle]);
    await expectLater(session.present(), throwsStateError);
    await session.dispose();
  });
  test('cancel before present prevents opening the sheet', () async {
    final session = await ImagePlayground.prepare();
    await session.cancel();
    await expectLater(session.present(), throwsStateError);
    await session.dispose();
  });
  test(
    'dispose cancels pending presentation and prevents further use',
    () async {
      host.wait = true;
      final session = await ImagePlayground.prepare();
      final showing = session.present();
      await Future.wait([session.dispose(), session.dispose()]);
      expect(await showing, isNull);
      expect(session.isDisposed, isTrue);
      expect(host.released, [1]);
      expect(() => session.handle, throwsStateError);
      await expectLater(session.info(), throwsStateError);
      await session.cancel();
    },
  );
  test('a second presentation on the same session is rejected', () async {
    final session = await ImagePlayground.prepare();
    await session.present();
    await expectLater(session.present(), throwsStateError);
    await session.dispose();
  });
  test(
    'a session keeps its original bindings after a test binding swap',
    () async {
      final session = await ImagePlayground.prepare();
      ImagePlaygroundBindings.instance = ImagePlaygroundBindings(
        host: FakeHost(),
        platform: platform,
      );
      await session.dispose();
      expect(host.released, [1]);
    },
  );
  test('global release clears all native sessions', () async {
    final first = await ImagePlayground.prepare();
    final second = await ImagePlayground.prepare();
    expect(await ImagePlayground.liveHandleCount(), 2);
    expect(await ImagePlayground.releaseAll(), 2);
    expect(await ImagePlayground.liveHandleCount(), 0);
    await first.dispose();
    await second.dispose();
  });
  test('future error codes remain inspectable', () {
    final error = ImagePlaygroundException.fromPlatformException(
      PlatformException(code: 'future', message: 'detail', details: 'domain:4'),
    );
    expect(error.code, ImagePlaygroundErrorCode.unknown);
    expect(error.details, 'domain:4');
    expect(error.toString(), contains('detail'));
  });
}

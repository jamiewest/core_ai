// End-to-end tests against the real Core AI framework. Run on an
// iOS 27+ / macOS 27+ device or simulator:
//
//   cd example && flutter test integration_test -d macos

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const affineAsset = 'assets/models/affine.aimodel';
const accumulatorAsset = 'assets/models/accumulator.aimodel';
const imageAsset = 'assets/models/image_to_tensor.aimodel';
const matmulAsset = 'assets/models/matmul_add.aimodel';

Matcher throwsCoreAI(CoreAIErrorCode code) =>
    throwsA(isA<CoreAIException>().having((e) => e.code, 'code', code));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String affinePath;

  setUpAll(() async {
    expect(await CoreAI.isSupported(), isTrue, reason: 'needs iOS/macOS 27');
    await CoreAI.releaseAll();
    affinePath = await CoreAI.assetPath(affineAsset);
  });

  tearDown(() async {
    expect(await CoreAI.liveHandleCount(), 0, reason: 'a test leaked handles');
  });

  group('device', () {
    testWidgets('reports architecture and compute units', (_) async {
      expect(await CoreAI.deviceArchitectureName(), isNotEmpty);
      expect(
        await CoreAI.availableComputeUnitKinds(),
        contains(ComputeUnitKind.cpu),
      );
      expect(await CoreAI.platformVersion(), isNotEmpty);
    });

    testWidgets('resolves specialization options', (_) async {
      final cpu = await SpecializationOptions.cpuOnly.resolve();
      expect(cpu.allowedComputeUnitKinds, {ComputeUnitKind.cpu});

      final preferred = await const SpecializationOptions.preferring(
        ComputeUnitKind.gpu,
        expectFrequentReshapes: true,
      ).resolve();
      expect(preferred.preferredComputeUnitKind, ComputeUnitKind.gpu);
      expect(preferred.expectFrequentReshapes, isTrue);
    });
  });

  group('models', () {
    testWidgets('loads a bundled model and describes it', (_) async {
      expect(Directory(affinePath).existsSync(), isTrue);
      final model = await AIModel.loadAsset(affineAsset);
      expect(model.functionNames, ['main']);

      final descriptor = (await model.functionDescriptor('main'))!;
      final x = descriptor.inputs['x']! as NDArrayDescriptor;
      expect(x.scalarType, ScalarType.float32);
      expect(x.shape, [3]);
      expect(x.hasDynamicShape, isFalse);
      expect(x.preferredStrides, isNotNull);
      expect(descriptor.outputs.keys, ['y']);
      expect(descriptor.isStateful, isFalse);
      expect(await model.functionDescriptor('missing'), isNull);

      final resolved = await model.resolveDynamicDimensions('main', 'x', [3]);
      expect(resolved.shape, [3]);
      await model.dispose();
    });

    testWidgets('runs a function', (_) async {
      final model = await AIModel.loadAsset(affineAsset);
      final function = await model.loadFunction();
      await model.dispose(); // functions outlive their model

      final outputs = await function.run({
        'x': NDArray.float32([1, 2, 3]),
      });
      final y = outputs.ndArray('y');
      expect(y.scalarType, ScalarType.float32);
      expect(y.shape, [3]);
      expect(y.toDoubleList(), [3, 5, 7]);
      await function.dispose();
    });

    testWidgets('runs with CPU-only specialization', (_) async {
      final model = await AIModel.load(
        affinePath,
        options: SpecializationOptions.cpuOnly,
      );
      final function = await model.loadFunction('main');
      final outputs = await function.run({
        'x': NDArray.float32([0, 1, -1]),
      });
      expect(outputs.ndArray('y').toDoubleList(), [1, 3, -1]);
      await function.dispose();
      await model.dispose();
    });

    testWidgets('runs a multi-input, multi-output function', (_) async {
      final model = await AIModel.loadAsset(matmulAsset);
      final function = await model.loadFunction();
      final outputs = await function.run({
        'a': NDArray.float32([0, 1, 2, 3, 4, 5], shape: [2, 3]),
        'b': NDArray.float32(List.filled(6, 1), shape: [3, 2]),
        'c': NDArray.float32(List.filled(4, 0.5), shape: [2, 2]),
      });
      expect(outputs.keys, unorderedEquals(['y', 'a_plus_1']));
      expect(outputs.ndArray('y').shape, [2, 2]);
      expect(outputs.ndArray('y').toDoubleList(), [3.5, 3.5, 12.5, 12.5]);
      expect(outputs.ndArray('a_plus_1').toDoubleList(), [1, 2, 3, 4, 5, 6]);
      await function.dispose();
      await model.dispose();
    });
  });

  group('native values', () {
    testWidgets('retained outputs feed the next run without copying', (
      _,
    ) async {
      final function = await _loadFunction(affineAsset);
      final first = await function.run(
        {
          'x': NDArray.float32([1, 2, 3]),
        },
        retain: {'y'},
      );
      final y = first.nativeValue('y');
      expect((await y.describe()).shape, [3]);

      final second = await function.run({'x': y});
      expect(second.ndArray('y').toDoubleList(), [7, 11, 15]);

      final all = await function.run({'x': y}, retainAll: true);
      expect(all['y'], isA<NativeValue>());
      await all.disposeNativeValues();
      await y.dispose();
      await function.dispose();
    });

    testWidgets('output views are updated in place', (_) async {
      final function = await _loadFunction(affineAsset);
      final view = await function.allocate('y');
      final outputs = await function.run(
        {
          'x': NDArray.float32([1, 2, 3]),
        },
        outputViews: {'y': view},
      );
      expect(outputs.containsKey('y'), isFalse);
      expect((await view.readNDArray()).toDoubleList(), [3, 5, 7]);
      await view.dispose();
      await function.dispose();
    });

    testWidgets('write, copy, zero and describe', (_) async {
      final value = await NativeValue.fromNDArray(NDArray.float32([1, 2, 3]));
      final copy = await value.copy();
      await value.write(NDArray.float32([4, 5, 6]));
      expect((await value.readNDArray()).toDoubleList(), [4, 5, 6]);
      expect((await copy.readNDArray()).toDoubleList(), [1, 2, 3]);

      await copy.zero();
      expect((await copy.readNDArray()).toDoubleList(), [0, 0, 0]);

      final info = await value.describe();
      expect(info.kind, NativeValueKind.ndArray);
      expect(info.scalarType, ScalarType.float32);
      expect(info.byteCount, 12);

      await expectLater(
        value.write(NDArray.float32([1, 2])),
        throwsCoreAI(CoreAIErrorCode.invalidArgument),
      );

      final zeros = await NativeValue.zeros(ScalarType.int4, [5]);
      expect((await zeros.describe()).scalarType, ScalarType.int4);
      await Future.wait([value.dispose(), copy.dispose(), zeros.dispose()]);
    });

    testWidgets('round-trips every scalar type as raw bytes', (_) async {
      for (final type in ScalarType.values) {
        final value = await NativeValue.zeros(type, [2, 3]);
        final array = await value.readNDArray();
        expect(array.scalarType, type, reason: type.name);
        expect(array.shape, [2, 3], reason: type.name);
        await value.dispose();
      }
    });
  });

  group('state', () {
    testWidgets('state accumulates across runs and resets', (_) async {
      final function = await _loadFunction(accumulatorAsset);
      expect(function.descriptor.states.keys, ['total']);
      final state = await function.makeState();
      final x = NDArray.float32([1, 2, 3]);

      await expectLater(
        function.run({'x': x}),
        throwsCoreAI(CoreAIErrorCode.invalidArgument),
      );

      late InferenceOutputs outputs;
      for (var i = 0; i < 3; i++) {
        outputs = await function.run({'x': x}, state: state);
      }
      expect(outputs.ndArray('y').toDoubleList(), [3, 6, 9]);
      expect((await state['total'].readNDArray()).toDoubleList(), [3, 6, 9]);

      await state.reset();
      outputs = await function.run({'x': x}, state: state);
      expect(outputs.ndArray('y').toDoubleList(), [1, 2, 3]);

      await state.dispose();
      await function.dispose();
    });
  });

  group('images', () {
    testWidgets('runs on a pixel buffer from Dart', (_) async {
      final function = await _loadFunction(imageAsset);
      final image = function.descriptor.inputs['image']! as ImageDescriptor;
      expect(image.pixelFormatType, PixelFormat.bgra32);
      expect((image.width, image.height), (4, 4));

      final rgba = Uint8List(4 * 4 * 4);
      for (var p = 0; p < 16; p++) {
        rgba.setAll(p * 4, [10, 20, 30, 255]);
      }
      final buffer = PixelBuffer.fromRgba8888(rgba, width: 4, height: 4);
      final outputs = await function.run({'image': buffer});
      final pixels = outputs.ndArray('pixels');
      expect(pixels.shape, [4, 4, 4]);
      expect(pixels.toDoubleList().sublist(0, 4), [30, 20, 10, 255]);
      await function.dispose();
    });

    testWidgets('decodes and resizes an encoded image natively', (_) async {
      final function = await _loadFunction(imageAsset);
      final png = await _solidPng(10, 20, 30, size: 16);
      final value = await NativeValue.fromEncodedImage(
        png,
        pixelFormatType: PixelFormat.bgra32,
        width: 4,
        height: 4,
      );
      final info = await value.describe();
      expect((info.width, info.height), (4, 4));

      final outputs = await function.run({'image': value});
      final first = outputs.ndArray('pixels').toDoubleList().sublist(0, 4);
      expect(first[0], closeTo(30, 2));
      expect(first[1], closeTo(20, 2));
      expect(first[2], closeTo(10, 2));
      expect(first[3], 255);

      final roundTrip = await value.readPixelBuffer();
      expect(roundTrip.toRgba8888().sublist(0, 3), [
        closeTo(10, 2),
        closeTo(20, 2),
        closeTo(30, 2),
      ]);
      final encoded = await value.encodeImage();
      expect(encoded.sublist(1, 4), 'PNG'.codeUnits);
      await value.dispose();
      await function.dispose();
    });

    testWidgets('allocates an image input from its descriptor', (_) async {
      final function = await _loadFunction(imageAsset);
      final input = await function.allocate('image', role: ValueRole.input);
      final outputs = await function.run({'image': input});
      expect(outputs.ndArray('pixels').toDoubleList(), everyElement(0));
      await input.dispose();
      await function.dispose();
    });
  });

  group('compute streams', () {
    testWidgets('pipelines encoded work', (_) async {
      final function = await _loadFunction(affineAsset);
      final stream = await ComputeStream.create();

      final first = await function.encode({
        'x': NDArray.float32([1, 2, 3]),
      }, stream: stream);
      final second = await function.encode({'x': first['y']!}, stream: stream);
      expect((await second['y']!.readNDArray()).toDoubleList(), [7, 11, 15]);
      await stream.completed();

      for (final value in [...first.values, ...second.values]) {
        await value.dispose();
      }
      await stream.dispose();
      await function.dispose();
    });

    testWidgets('encodes stateful work', (_) async {
      final function = await _loadFunction(accumulatorAsset);
      final stream = await ComputeStream.create();
      final state = await function.makeState();
      final x = NDArray.float32([1, 2, 3]);

      final outputs = <Map<String, NativeValue>>[];
      for (var i = 0; i < 3; i++) {
        outputs.add(
          await function.encode({'x': x}, stream: stream, state: state),
        );
      }
      expect((await state['total'].describe()).kind, isNotNull);
      expect((await outputs.last['y']!.readNDArray()).toDoubleList(), [
        3,
        6,
        9,
      ]);
      await stream.completed();
      expect((await state['total'].readNDArray()).toDoubleList(), [3, 6, 9]);

      for (final map in outputs) {
        await Future.wait(map.values.map((value) => value.dispose()));
      }
      await state.dispose();
      await stream.dispose();
      await function.dispose();
    });
  });

  group('cache', () {
    testWidgets('specializes, bookmarks and deletes cache entries', (_) async {
      final cache = AIModelCache.shared;
      expect(await cache.isAvailable(), isTrue);
      expect(
        await const AIModelCache.appGroup('invalid.group').isAvailable(),
        isFalse,
      );

      const options = SpecializationOptions.preferring(ComputeUnitKind.cpu);
      final model = await AIModel.specialize(
        affinePath,
        options: options,
        policy: CachePolicy.persistent,
      );
      final bookmark = await model.bookmarkData();
      expect(bookmark, isNotEmpty);

      final cached = await cache.model(affinePath, options: options);
      expect(cached, isNotNull);
      final restored = await AIModel.fromBookmark(bookmark);
      expect(restored, isNotNull);
      final function = await restored!.loadFunction();
      final outputs = await function.run({
        'x': NDArray.float32([1, 1, 1]),
      });
      expect(outputs.ndArray('y').toDoubleList(), [3, 3, 3]);

      await function.dispose();
      await Future.wait([
        model.dispose(),
        cached!.dispose(),
        restored.dispose(),
      ]);

      await cache.deleteEntry(affinePath, options: options);
      expect(await cache.model(affinePath, options: options), isNull);
      expect(await AIModel.fromBookmark(bookmark), isNull);
    });
  });

  group('assets', () {
    testWidgets('reads a summary and updates metadata', (_) async {
      expect(await AIModelAsset.isValid(affinePath), isTrue);
      expect(await AIModelAsset.isValid('/nonexistent.aimodel'), isFalse);

      final summary = await AIModelAsset(
        affinePath,
      ).summary(includeStatistics: true);
      expect(summary, isNotNull);
      expect(summary!.functions.single.name, 'main');
      expect(summary.functions.single.inputs.single.name, 'x');

      final copy = await _copyDirectory(affinePath);
      final asset = AIModelAsset(copy);
      await asset.updateMetadata(
        author: 'core_ai tests',
        license: 'MIT',
        description: 'y = 2x + 1',
        creationDate: DateTime.utc(2026, 9, 18),
        creatorDefined: {
          'version': 2,
          'scale': 0.5,
          'enabled': true,
          // Core AI (macOS/iOS 27.0) reads integers 0 and 1 in creator-defined
          // metadata back as Booleans, so avoid them here.
          'tags': ['a', 7],
          'nested': {'k': 'v'},
        },
      );
      var metadata = await asset.metadata();
      expect(metadata.author, 'core_ai tests');
      expect(metadata.license, 'MIT');
      expect(metadata.description, 'y = 2x + 1');
      expect(metadata.creationDate, DateTime.utc(2026, 9, 18));
      expect(metadata.creatorDefined, {
        'version': 2,
        'scale': 0.5,
        'enabled': true,
        'tags': ['a', 7],
        'nested': {'k': 'v'},
      });

      await asset.updateMetadata(
        removeCreatorDefined: ['tags'],
        clearCreationDate: true,
      );
      metadata = await asset.metadata();
      expect(metadata.creatorDefined.containsKey('tags'), isFalse);
      expect(metadata.creationDate, isNull);

      await asset.removeDerivedArtifacts();
      expect(await AIModelAsset.isValid(copy), isTrue);
      await Directory(copy).parent.delete(recursive: true);
    });
  });

  group('errors', () {
    testWidgets('reports missing models and functions', (_) async {
      await expectLater(
        AIModel.load('/nonexistent/Model.aimodel'),
        throwsCoreAI(CoreAIErrorCode.notFound),
      );
      await expectLater(
        AIModel.loadAsset('assets/missing.aimodel'),
        throwsCoreAI(CoreAIErrorCode.notFound),
      );
      final model = await AIModel.loadAsset(affineAsset);
      await expectLater(
        model.loadFunction('missing'),
        throwsCoreAI(CoreAIErrorCode.notFound),
      );
      await model.dispose();
    });

    testWidgets('reports Core AI inference errors', (_) async {
      final function = await _loadFunction(affineAsset);
      await expectLater(
        function.run({
          'x': NDArray.int32([1, 2, 3]),
        }),
        throwsA(isA<CoreAIException>()),
      );
      await function.dispose();
      expect(
        () => function.run({
          'x': NDArray.float32([1, 2, 3]),
        }),
        throwsStateError,
      );
    });

    testWidgets('rejects a value used as input and state at once', (_) async {
      final function = await _loadFunction(accumulatorAsset);
      final state = await function.makeState();
      await expectLater(
        function.run({'x': state['total']}, state: state),
        throwsCoreAI(CoreAIErrorCode.busy),
      );
      await state.dispose();
      await function.dispose();
    });
  });
}

Future<InferenceFunction> _loadFunction(String asset) async {
  final model = await AIModel.loadAsset(asset);
  final function = await model.loadFunction();
  await model.dispose();
  return function;
}

Future<Uint8List> _solidPng(int r, int g, int b, {required int size}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = ui.Color.fromARGB(255, r, g, b),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<String> _copyDirectory(String source) async {
  final root = await Directory.systemTemp.createTemp('core_ai_asset_');
  final target = Directory('${root.path}/${source.split('/').last}');
  await target.create();
  for (final entity in Directory(source).listSync()) {
    if (entity is File) {
      await entity.copy('${target.path}/${entity.uri.pathSegments.last}');
    }
  }
  return target.path;
}

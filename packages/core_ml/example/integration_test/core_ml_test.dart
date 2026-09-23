// End-to-end tests against the real Core ML framework, using the tiny models
// in assets/models (see tool/models/README.md). Run on macOS 15+ / iOS 18+:
//
//   cd example && flutter test integration_test/core_ml_test.dart -d macos

import 'dart:io';
import 'dart:typed_data';

import 'package:core_ml/core_ml.dart';
import 'package:core_ml/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const affineAsset = 'assets/models/affine.mlpackage';
const multiAsset = 'assets/models/multi_io.mlpackage';
const imageAsset = 'assets/models/image_input.mlpackage';
const statefulAsset = 'assets/models/stateful.mlpackage';
const classifierAsset = 'assets/models/classifier.mlpackage';
const multifunctionAsset = 'assets/models/multifunction.mlpackage';

Matcher throwsCoreML(CoreMLErrorCode code) =>
    throwsA(isA<CoreMLException>().having((e) => e.code, 'code', code));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;
  late String affineCompiled;

  setUpAll(() async {
    expect(await CoreML.isSupported(), isTrue, reason: 'needs macOS 15+');
    await CoreML.releaseAll();
    scratch = await Directory.systemTemp.createTemp('core_ml_test');
    // Compile once and persist, so later tests load the .mlmodelc directly.
    affineCompiled = await MLModel.compile(
      await CoreML.assetPath(affineAsset),
      destination: '${scratch.path}/affine.mlmodelc',
    );
  });

  tearDownAll(() async {
    if (scratch.existsSync()) await scratch.delete(recursive: true);
  });

  tearDown(() async {
    expect(await CoreML.liveHandleCount(), 0, reason: 'a test leaked handles');
  });

  group('compilation and loading', () {
    testWidgets('bundles every file of the .mlpackage', (_) async {
      final path = await CoreML.assetPath(affineAsset);
      expect(File('$path/Manifest.json').existsSync(), isTrue);
      expect(
        File('$path/Data/com.apple.CoreML/model.mlmodel').existsSync(),
        isTrue,
      );
    });

    testWidgets('compiles to a persisted .mlmodelc and predicts', (_) async {
      expect(affineCompiled, '${scratch.path}/affine.mlmodelc');
      expect(Directory(affineCompiled).existsSync(), isTrue);
      final model = await MLModel.load(affineCompiled);
      final prediction = await model.predict({
        'x': MLMultiArray.float32([1, 2, 3]),
      });
      final y = prediction.multiArray('y');
      expect(y.dataType, MLMultiArrayDataType.float32);
      expect(y.shape, [3]);
      expect(y.toDoubleList(), [3, 5, 7]);
      await model.dispose();
    });

    testWidgets('compiles to a temporary directory by default', (_) async {
      final compiled = await MLModel.compile(
        await CoreML.assetPath(multiAsset),
      );
      expect(compiled, endsWith('.mlmodelc'));
      expect(Directory(compiled).existsSync(), isTrue);
    });

    testWidgets('loadAsset compiles and loads in one step', (_) async {
      final model = await MLModel.loadAsset(affineAsset);
      final prediction = await model.predict({
        'x': MLMultiArray.float32([0, -1, 0.5]),
      });
      expect(prediction.multiArray('y').toDoubleList(), [1, -1, 2]);
      await model.dispose();
    });

    testWidgets('lists functions and describes a compiled model', (_) async {
      // Single-function models report no function names.
      expect(await MLModel.functionNames(affineCompiled), isEmpty);
      final description = await MLModel.describe(affineCompiled);
      expect(description.inputs.keys, ['x']);
      expect(description.outputs.keys, ['y']);
    });

    testWidgets('selects a function of a multi-function model', (_) async {
      final compiled = await MLModel.compile(
        await CoreML.assetPath(multifunctionAsset),
        destination: '${scratch.path}/multifunction.mlmodelc',
      );
      expect(
        await MLModel.functionNames(compiled),
        unorderedEquals(['double', 'negate']),
      );
      final negateDescription = await MLModel.describe(
        compiled,
        functionName: 'negate',
      );
      expect(negateDescription.inputs.keys, ['x']);

      final x = MLMultiArray.float32([1, 2, 3]);
      final byDefault = await MLModel.load(compiled);
      expect(
        (await byDefault.predict({'x': x})).multiArray('y').toDoubleList(),
        [2, 4, 6],
      );
      final negate = await MLModel.load(
        compiled,
        configuration: const MLModelConfiguration(functionName: 'negate'),
      );
      expect(negate.configuration.functionName, 'negate');
      expect((await negate.predict({'x': x})).multiArray('y').toDoubleList(), [
        -1,
        -2,
        -3,
      ]);
      await expectLater(
        MLModel.load(
          compiled,
          configuration: const MLModelConfiguration(functionName: 'missing'),
        ),
        throwsA(isA<CoreMLException>()),
      );
      await byDefault.dispose();
      await negate.dispose();
    });
  });

  group('configuration', () {
    for (final units in MLComputeUnits.values) {
      testWidgets('predicts with ${units.name}', (_) async {
        final model = await MLModel.load(
          affineCompiled,
          configuration: MLModelConfiguration(
            computeUnits: units,
            modelDisplayName: 'affine-${units.name}',
          ),
        );
        expect(model.configuration.computeUnits, units);
        expect(model.configuration.modelDisplayName, 'affine-${units.name}');
        final prediction = await model.predict({
          'x': MLMultiArray.float32([1, 2, 3]),
        });
        // Anything but the CPU may compute in float16.
        final y = prediction.multiArray('y').toDoubleList();
        for (final (index, value) in [3.0, 5.0, 7.0].indexed) {
          expect(y[index], closeTo(value, 0.01));
        }
        await model.dispose();
      });
    }

    testWidgets('applies optimization hints and GPU options', (_) async {
      final model = await MLModel.load(
        affineCompiled,
        configuration: const MLModelConfiguration(
          computeUnits: MLComputeUnits.cpuAndGpu,
          allowLowPrecisionAccumulationOnGPU: true,
          reshapeFrequency: MLReshapeFrequency.infrequent,
          specializationStrategy: MLSpecializationStrategy.fastPrediction,
        ),
      );
      expect(model.configuration.allowLowPrecisionAccumulationOnGPU, isTrue);
      expect(
        model.configuration.reshapeFrequency,
        MLReshapeFrequency.infrequent,
      );
      expect(
        model.configuration.specializationStrategy,
        MLSpecializationStrategy.fastPrediction,
      );
      await model.dispose();
    });

    testWidgets('reports compute devices', (_) async {
      final available = await CoreML.availableComputeDevices();
      expect(available.map((d) => d.kind), contains(MLComputeDeviceKind.cpu));
      final all = await CoreML.allComputeDevices();
      expect(all.length, greaterThanOrEqualTo(available.length));
      final gpu = all.where((d) => d.kind == MLComputeDeviceKind.gpu);
      for (final device in gpu) {
        expect(device.metalDeviceName, isNotEmpty);
      }
    });
  });

  group('description', () {
    testWidgets('describes features and metadata', (_) async {
      final model = await MLModel.load(affineCompiled);
      final description = model.modelDescription;
      final x = description.inputs['x']!;
      expect(x.type, MLFeatureType.multiArray);
      expect(x.isOptional, isFalse);
      expect(x.multiArrayConstraint!.dataType, MLMultiArrayDataType.float32);
      expect(x.multiArrayConstraint!.shape, [3]);
      expect(description.outputs['y']!.type, MLFeatureType.multiArray);
      expect(description.isStateful, isFalse);
      expect(description.isUpdatable, isFalse);
      expect(description.classLabels, isNull);

      final metadata = description.metadata;
      expect(metadata.author, 'core_ml tests');
      expect(metadata.license, 'MIT');
      expect(metadata.description, 'y = x * 2 + 1');
      expect(metadata.versionString, '1.0');
      expect(
        metadata.creatorDefined['com.github.apple.coremltools.version'],
        '9.0',
      );
      await model.dispose();
    });

    testWidgets('describes a classifier', (_) async {
      final model = await MLModel.loadAsset(classifierAsset);
      final description = model.modelDescription;
      expect(description.classLabels, ['ant', 'bee', 'cat']);
      expect(description.predictedFeatureName, 'classLabel');
      expect(description.predictedProbabilitiesName, 'classLabel_probs');
      expect(description.outputs['classLabel']!.type, MLFeatureType.string);
      final probabilities = description.outputs['classLabel_probs']!;
      expect(probabilities.type, MLFeatureType.dictionary);
      expect(probabilities.dictionaryConstraint!.keyType, MLFeatureType.string);
      await model.dispose();
    });

    testWidgets('describes image inputs and states', (_) async {
      final image = await MLModel.loadAsset(imageAsset);
      final constraint = image.modelDescription.inputs['image']!;
      expect(constraint.type, MLFeatureType.image);
      expect(constraint.imageConstraint!.pixelsWide, 4);
      expect(constraint.imageConstraint!.pixelsHigh, 4);
      expect(constraint.imageConstraint!.pixelFormatType, PixelFormat.bgra32);
      await image.dispose();

      final stateful = await MLModel.loadAsset(statefulAsset);
      final total = stateful.modelDescription.states['total']!;
      expect(total.type, MLFeatureType.state);
      expect(total.stateConstraint!.dataType, MLMultiArrayDataType.float16);
      expect(total.stateConstraint!.bufferShape, [3]);
      expect(stateful.modelDescription.isStateful, isTrue);
      await stateful.dispose();
    });
  });

  group('prediction', () {
    testWidgets('multiple inputs and outputs', (_) async {
      final model = await MLModel.loadAsset(multiAsset);
      final prediction = await model.predict({
        'a': MLMultiArray.float32([0, 1, 2, 3, 4, 5], shape: [2, 3]),
        'b': MLMultiArray.float32(List.filled(6, 1), shape: [3, 2]),
        'c': MLMultiArray.float32(List.filled(4, 0.5), shape: [2, 2]),
      });
      expect(prediction.keys, unorderedEquals(['y', 'a_plus_1']));
      expect(prediction.multiArray('y').shape, [2, 2]);
      expect(prediction.multiArray('y').toDoubleList(), [3.5, 3.5, 12.5, 12.5]);
      expect(prediction.multiArray('a_plus_1').toDoubleList(), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      await model.dispose();
    });

    testWidgets('accepts other multi-array types and strides', (_) async {
      final model = await MLModel.load(affineCompiled);
      // float64 input to a float32 feature: Core ML converts it.
      final fromDouble = await model.predict({
        'x': MLMultiArray.float64([1, 2, 3]),
      });
      expect(fromDouble.multiArray('y').toDoubleList(), [3, 5, 7]);

      // Non-contiguous storage: every other element of 6 floats.
      final strided = MLMultiArray.fromBytes(
        Float32List.fromList([1, -9, 2, -9, 3]).buffer.asUint8List(),
        dataType: MLMultiArrayDataType.float32,
        shape: [3],
        strides: [2],
      );
      final fromStrided = await model.predict({'x': strided});
      expect(fromStrided.multiArray('y').toDoubleList(), [3, 5, 7]);
      await model.dispose();
    });

    testWidgets('classifier outputs a label and a dictionary', (_) async {
      final model = await MLModel.loadAsset(classifierAsset);
      final prediction = await model.predict({
        'scores': MLMultiArray.float32([0, 5, 1], shape: [1, 3]),
      });
      expect(prediction.stringValue('classLabel'), 'bee');
      final probabilities = prediction.dictionary('classLabel_probs');
      expect(
        probabilities.stringKeyed!.keys,
        unorderedEquals(['ant', 'bee', 'cat']),
      );
      expect(probabilities.stringKeyed!['bee'], closeTo(0.9756, 1e-3));
      expect(probabilities.stringKeyed!['ant'], closeTo(0.00657, 1e-4));
      await model.dispose();
    });

    testWidgets('batch prediction keeps input order', (_) async {
      final model = await MLModel.load(affineCompiled);
      final results = await model.predictBatch([
        {
          'x': MLMultiArray.float32([1, 2, 3]),
        },
        {
          'x': MLMultiArray.float32([0, 0, 0]),
        },
        {
          'x': MLMultiArray.float32([10, 20, 30]),
        },
      ]);
      expect(results, hasLength(3));
      expect(results[0].multiArray('y').toDoubleList(), [3, 5, 7]);
      expect(results[1].multiArray('y').toDoubleList(), [1, 1, 1]);
      expect(results[2].multiArray('y').toDoubleList(), [21, 41, 61]);
      await model.dispose();
    });

    testWidgets('concurrent predictions on one model', (_) async {
      final model = await MLModel.load(affineCompiled);
      final results = await Future.wait([
        for (var i = 0; i < 8; i++)
          model.predict({
            'x': MLMultiArray.float32([i, i, i]),
          }),
      ]);
      for (final (i, result) in results.indexed) {
        expect(
          result.multiArray('y').toDoubleList(),
          List.filled(3, 2 * i + 1),
        );
      }
      await model.dispose();
    });
  });

  group('images', () {
    PixelBuffer solidBgra(int size, int b, int g, int r) => PixelBuffer.packed(
      width: size,
      height: size,
      pixelFormatType: PixelFormat.bgra32,
      bytes: Uint8List.fromList([
        for (var i = 0; i < size * size; i++) ...[b, g, r, 255],
      ]),
    );

    void expectChannels(MLMultiArray pixels, List<double> bgr) {
      expect(pixels.shape, [1, 3, 4, 4]);
      final values = pixels.toDoubleList();
      for (var channel = 0; channel < 3; channel++) {
        for (var i = 0; i < 16; i++) {
          expect(values[channel * 16 + i], closeTo(bgr[channel], 1.01));
        }
      }
    }

    testWidgets('raw pixels', (_) async {
      final model = await MLModel.loadAsset(imageAsset);
      final prediction = await model.predict({
        'image': solidBgra(4, 10, 20, 30),
      });
      final pixels = prediction.multiArray('pixels');
      expect(pixels.toDoubleList().take(16), everyElement(10));
      expectChannels(pixels, [10, 20, 30]);
      await model.dispose();
    });

    testWidgets('encoded bytes and files, resized to the constraint', (
      _,
    ) async {
      final png = await CoreML.encodeImage(solidBgra(16, 40, 80, 120));
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      final file = File('${scratch.path}/solid.png')..writeAsBytesSync(png);

      final model = await MLModel.loadAsset(imageAsset);
      final fromBytes = await model.predict({'image': ImageInput.encoded(png)});
      expectChannels(fromBytes.multiArray('pixels'), [40, 80, 120]);
      final fromFile = await model.predict({
        'image': ImageInput.file(file.path),
      });
      expectChannels(fromFile.multiArray('pixels'), [40, 80, 120]);
      await model.dispose();
    });
  });

  group('state', () {
    testWidgets('accumulates across predictions', (_) async {
      final model = await MLModel.loadAsset(statefulAsset);
      final state = await model.makeState();
      expect(state.stateNames, ['total']);
      expect((await state.read('total')).toDoubleList(), [0, 0, 0]);

      final x = MLMultiArray.float16([1, 2, 3]);
      for (var step = 1; step <= 3; step++) {
        final prediction = await model.predict({'x': x}, state: state);
        final y = prediction.multiArray('y');
        expect(y.dataType, MLMultiArrayDataType.float16);
        expect(y.toDoubleList(), [step * 1.0, step * 2.0, step * 3.0]);
      }
      final total = await state.read('total');
      expect(total.dataType, MLMultiArrayDataType.float16);
      expect(total.toDoubleList(), [3, 6, 9]);

      await state.write('total', MLMultiArray.float16([100, 0, -0.5]));
      final after = await model.predict({'x': x}, state: state);
      expect(after.multiArray('y').toDoubleList(), [101, 2, 2.5]);

      // A fresh state starts from zero again.
      final fresh = await model.makeState();
      final first = await model.predict({'x': x}, state: fresh);
      expect(first.multiArray('y').toDoubleList(), [1, 2, 3]);

      await fresh.dispose();
      await state.dispose();
      await model.dispose();
    });

    testWidgets('state outlives its model handle', (_) async {
      final model = await MLModel.loadAsset(statefulAsset);
      final state = await model.makeState();
      await model.dispose();
      expect((await state.read('total')).toDoubleList(), [0, 0, 0]);
      await state.dispose();
    });
  });

  group('errors', () {
    testWidgets('missing files', (_) async {
      await expectLater(
        MLModel.load('${scratch.path}/missing.mlmodelc'),
        throwsCoreML(CoreMLErrorCode.notFound),
      );
      await expectLater(
        MLModel.compile('${scratch.path}/missing.mlpackage'),
        throwsCoreML(CoreMLErrorCode.notFound),
      );
      await expectLater(
        CoreML.assetPath('assets/models/missing.mlpackage'),
        throwsCoreML(CoreMLErrorCode.notFound),
      );
    });

    testWidgets('compiling something that is not a model', (_) async {
      final bogus = File('${scratch.path}/bogus.mlmodel')
        ..writeAsStringSync('not a model');
      await expectLater(
        MLModel.compile(bogus.path),
        throwsA(isA<CoreMLException>()),
      );
    });

    testWidgets('bad inputs', (_) async {
      final model = await MLModel.load(affineCompiled);
      // Missing input.
      await expectLater(model.predict({}), throwsA(isA<CoreMLException>()));
      // Wrong feature type.
      await expectLater(
        model.predict({'x': const MLFeatureValue.string('nope')}),
        throwsA(isA<CoreMLException>()),
      );
      // Wrong shape.
      await expectLater(
        model.predict({
          'x': MLMultiArray.float32([1, 2]),
        }),
        throwsA(isA<CoreMLException>()),
      );
      // Storage that does not match the layout is rejected natively too
      // (the public API already checks it in Dart).
      final host = CoreMLBindings.instance.host;
      await expectLater(
        host.predict(
          PredictionRequestMessage(
            modelHandle: model.handle,
            inputs: {
              'x': MultiArrayMessage(
                dataType: MultiArrayDataTypeMessage.float32,
                shape: [3],
                strides: [],
                data: Uint8List(8),
              ),
            },
          ),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'invalid_argument',
          ),
        ),
      );
      await model.dispose();
    });

    testWidgets('state misuse', (_) async {
      final model = await MLModel.loadAsset(statefulAsset);
      await expectLater(
        model.predict({
          'x': MLMultiArray.float16([1, 2, 3]),
        }),
        throwsCoreML(CoreMLErrorCode.invalidArgument),
      );
      final state = await model.makeState();
      await expectLater(
        state.read('missing'),
        throwsCoreML(CoreMLErrorCode.notFound),
      );
      await expectLater(
        state.write('total', MLMultiArray.float32([1, 2, 3])),
        throwsCoreML(CoreMLErrorCode.invalidArgument),
      );
      await state.dispose();
      await model.dispose();
    });

    testWidgets('use after dispose', (_) async {
      final model = await MLModel.load(affineCompiled);
      await model.dispose();
      await model.dispose(); // idempotent
      expect(
        () => model.predict({
          'x': MLMultiArray.float32([1, 2, 3]),
        }),
        throwsStateError,
      );
    });

    testWidgets('releaseAll frees leaked handles', (_) async {
      await MLModel.load(affineCompiled);
      final model = await MLModel.load(affineCompiled);
      await model.makeState();
      expect(await CoreML.liveHandleCount(), 3);
      expect(await CoreML.releaseAll(), 3);
      await expectLater(
        model.predict({
          'x': MLMultiArray.float32([1, 2, 3]),
        }),
        throwsCoreML(CoreMLErrorCode.invalidHandle),
      );
    });
  });
}

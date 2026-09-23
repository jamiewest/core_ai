import 'package:core_ml/core_ml.dart';
import 'package:core_ml/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake `CoreMLHostApi` that records calls and answers from canned data.
class FakeHost implements CoreMLHostApi {
  final calls = <String>[];
  final released = <int>[];
  int nextHandle = 1;
  PredictionRequestMessage? lastPrediction;
  BatchPredictionRequestMessage? lastBatch;
  ModelConfigurationMessage? lastConfiguration;
  Map<String, FeatureValueMessage> outputs = {};
  ModelDescriptionMessage description = _description();
  Object? error;
  MultiArrayMessage? writtenState;

  void _maybeThrow() {
    final pending = error;
    if (pending != null) throw pending;
  }

  @override
  Future<String> compileModel(String path, String? destinationPath) async {
    calls.add('compile $path -> $destinationPath');
    _maybeThrow();
    return destinationPath ?? '/tmp/compiled.mlmodelc';
  }

  @override
  Future<ModelInfoMessage> loadModel(
    String compiledPath,
    ModelConfigurationMessage configuration,
  ) async {
    calls.add('load $compiledPath');
    _maybeThrow();
    lastConfiguration = configuration;
    return ModelInfoMessage(
      handle: nextHandle++,
      modelDescription: description,
      configuration: configuration,
    );
  }

  @override
  Future<List<String>> functionNames(String compiledPath) async => ['a', 'b'];

  @override
  Future<ModelDescriptionMessage> assetModelDescription(
    String compiledPath,
    String? functionName,
  ) async {
    calls.add('describe $compiledPath $functionName');
    return description;
  }

  @override
  Future<PredictionResultMessage> predict(
    PredictionRequestMessage request,
  ) async {
    _maybeThrow();
    lastPrediction = request;
    return PredictionResultMessage(outputs: outputs);
  }

  @override
  Future<BatchPredictionResultMessage> predictBatch(
    BatchPredictionRequestMessage request,
  ) async {
    lastBatch = request;
    return BatchPredictionResultMessage(
      outputs: [
        for (var i = 0; i < request.inputs.length; i++)
          FeatureMapMessage(features: {'i': Int64ValueMessage(value: i)}),
      ],
    );
  }

  @override
  Future<int> makeState(int modelHandle) async {
    calls.add('makeState $modelHandle');
    return nextHandle++;
  }

  @override
  Future<MultiArrayMessage> readState(int stateHandle, String stateName) async {
    calls.add('readState $stateHandle $stateName');
    return MLMultiArray.float16([1, 2, 3]).toMessage();
  }

  @override
  Future<void> writeState(
    int stateHandle,
    String stateName,
    MultiArrayMessage array,
  ) async {
    calls.add('writeState $stateHandle $stateName');
    writtenState = array;
  }

  @override
  Future<List<ComputeDeviceMessage>> availableComputeDevices() async => [
    ComputeDeviceMessage(kind: ComputeDeviceKindMessage.cpu, name: 'CPU'),
    ComputeDeviceMessage(
      kind: ComputeDeviceKindMessage.neuralEngine,
      name: 'Neural Engine',
      neuralEngineCoreCount: 16,
    ),
  ];

  @override
  Future<void> release(int handle) async => released.add(handle);

  @override
  Future<int> releaseAll() async => 0;

  @override
  Future<int> liveHandleCount() async => 7;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlatform implements CoreMLPlatformApi {
  FakePlatform({this.supported = true, this.paths = const {}});

  final bool supported;
  final Map<String, String> paths;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<String> platformVersion() async => 'macOS 27.0';

  @override
  Future<String?> assetPath(String assetKey, String? package) async =>
      paths[assetKey];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ThrowingPlatform extends FakePlatform {
  @override
  Future<bool> isSupported() => throw MissingPluginException();
}

FeatureDescriptionMessage _multiArray(String name) => FeatureDescriptionMessage(
  name: name,
  type: FeatureTypeMessage.multiArray,
  optional: false,
  multiArrayConstraint: MultiArrayConstraintMessage(
    dataType: MultiArrayDataTypeMessage.float32,
    shape: [3],
    shapeConstraintType: ShapeConstraintTypeMessage.range,
    enumeratedShapes: [
      ShapeMessage(dimensions: [3]),
    ],
    minimumSizes: [1],
    maximumSizes: [-1],
  ),
);

ModelDescriptionMessage _description({
  List<FeatureDescriptionMessage> states = const [],
}) => ModelDescriptionMessage(
  inputs: [
    _multiArray('x'),
    FeatureDescriptionMessage(
      name: 'image',
      type: FeatureTypeMessage.image,
      optional: true,
      imageConstraint: ImageConstraintMessage(
        pixelsWide: 224,
        pixelsHigh: 224,
        pixelFormatType: 0x42475241,
        sizeConstraintType: ImageSizeConstraintTypeMessage.enumerated,
        enumeratedSizes: [ImageSizeMessage(width: 224, height: 224)],
        minimumWidth: 224,
        maximumWidth: 224,
        minimumHeight: 224,
        maximumHeight: 224,
      ),
    ),
  ],
  outputs: [
    FeatureDescriptionMessage(
      name: 'probs',
      type: FeatureTypeMessage.dictionary,
      optional: false,
      dictionaryConstraint: DictionaryConstraintMessage(
        keyType: FeatureTypeMessage.string,
      ),
    ),
    FeatureDescriptionMessage(
      name: 'tokens',
      type: FeatureTypeMessage.sequence,
      optional: false,
      sequenceConstraint: SequenceConstraintMessage(
        valueType: FeatureTypeMessage.int64,
        minimumCount: 0,
        maximumCount: -1,
      ),
    ),
  ],
  states: states,
  trainingInputs: [],
  predictedFeatureName: 'label',
  predictedProbabilitiesName: 'probs',
  classLabelStrings: ['a', 'b'],
  isUpdatable: false,
  metadata: ModelMetadataMessage(
    author: 'me',
    license: 'MIT',
    modelDescription: 'desc',
    versionString: '2',
    creatorDefined: {'k': 'v'},
  ),
);

Matcher throwsCoreML(CoreMLErrorCode code) =>
    throwsA(isA<CoreMLException>().having((e) => e.code, 'code', code));

void main() {
  late FakeHost host;

  setUp(() {
    host = FakeHost();
    CoreMLBindings.instance = CoreMLBindings(
      host: host,
      platform: FakePlatform(
        paths: {'assets/m.mlpackage': '/bundle/m.mlpackage'},
      ),
    );
  });

  group('CoreML', () {
    test('reports support and devices', () async {
      expect(await CoreML.isSupported(), isTrue);
      expect(await CoreML.platformVersion(), 'macOS 27.0');
      expect(await CoreML.liveHandleCount(), 7);
      final devices = await CoreML.availableComputeDevices();
      expect(devices.map((d) => d.kind), [
        MLComputeDeviceKind.cpu,
        MLComputeDeviceKind.neuralEngine,
      ]);
      expect(devices.last.neuralEngineCoreCount, 16);
    });

    test('isSupported is false without a plugin', () async {
      CoreMLBindings.instance = CoreMLBindings(
        host: host,
        platform: ThrowingPlatform(),
      );
      expect(await CoreML.isSupported(), isFalse);
    });
  });

  group('loading', () {
    test('sends the configuration and maps the description', () async {
      final model = await MLModel.load(
        '/m.mlmodelc',
        configuration: const MLModelConfiguration(
          computeUnits: MLComputeUnits.cpuAndNeuralEngine,
          allowLowPrecisionAccumulationOnGPU: true,
          functionName: 'decode',
          modelDisplayName: 'demo',
          reshapeFrequency: MLReshapeFrequency.infrequent,
          specializationStrategy: MLSpecializationStrategy.fastPrediction,
        ),
      );
      final sent = host.lastConfiguration!;
      expect(sent.computeUnits, ComputeUnitsMessage.cpuAndNeuralEngine);
      expect(sent.allowLowPrecisionAccumulationOnGPU, isTrue);
      expect(sent.functionName, 'decode');
      expect(sent.modelDisplayName, 'demo');
      expect(sent.reshapeFrequency, ReshapeFrequencyMessage.infrequent);
      expect(
        sent.specializationStrategy,
        SpecializationStrategyMessage.fastPrediction,
      );
      expect(model.configuration.functionName, 'decode');
      expect(
        model.configuration.specializationStrategy,
        MLSpecializationStrategy.fastPrediction,
      );

      final description = model.modelDescription;
      expect(description.inputs.keys, ['x', 'image']);
      final x = description.inputs['x']!.multiArrayConstraint!;
      expect(x.dataType, MLMultiArrayDataType.float32);
      expect(x.shapeConstraintType, MLShapeConstraintType.range);
      expect(x.enumeratedShapes, [
        [3],
      ]);
      expect(x.maximumSizes, [-1]);
      final image = description.inputs['image']!;
      expect(image.isOptional, isTrue);
      expect(image.imageConstraint!.pixelFormatType, PixelFormat.bgra32);
      expect(image.imageConstraint!.enumeratedSizes, [
        const MLImageSize(width: 224, height: 224),
      ]);
      expect(
        description.outputs['probs']!.dictionaryConstraint!.keyType,
        MLFeatureType.string,
      );
      expect(
        description.outputs['tokens']!.sequenceConstraint!.valueType,
        MLFeatureType.int64,
      );
      expect(description.classLabels, ['a', 'b']);
      expect(description.predictedFeatureName, 'label');
      expect(description.metadata.description, 'desc');
      expect(description.metadata.creatorDefined, {'k': 'v'});
      expect(description.isStateful, isFalse);
      await model.dispose();
    });

    test('compileAndLoad skips compiling a .mlmodelc', () async {
      final compiled = await MLModel.compileAndLoad('/x/m.mlmodelc/');
      expect(host.calls, ['load /x/m.mlmodelc/']);
      await compiled.dispose();

      host.calls.clear();
      final model = await MLModel.loadAsset(
        'assets/m.mlpackage/',
        compiledDestination: '/cache/m.mlmodelc',
      );
      expect(host.calls, [
        'compile /bundle/m.mlpackage -> /cache/m.mlmodelc',
        'load /cache/m.mlmodelc',
      ]);
      await model.dispose();
    });

    test('missing assets are reported', () async {
      await expectLater(
        MLModel.loadAsset('assets/missing.mlpackage'),
        throwsCoreML(CoreMLErrorCode.notFound),
      );
    });

    test('asset queries', () async {
      expect(await MLModel.functionNames('/m.mlmodelc'), ['a', 'b']);
      final description = await MLModel.describe(
        '/m.mlmodelc',
        functionName: 'b',
      );
      expect(host.calls.last, 'describe /m.mlmodelc b');
      expect(description.inputs, contains('x'));
    });
  });

  group('prediction', () {
    test('maps every input kind to a message', () async {
      final model = await MLModel.load('/m.mlmodelc');
      await model.predict({
        'array': MLMultiArray.float32([1, 2, 3]),
        'file': const ImageInput.file('/a.png'),
        'bytes': ImageInput.encoded(Uint8List.fromList([9])),
        'pixels': ImageInput.pixels(width: 1, height: 1, bytes: Uint8List(4)),
        'text': const MLFeatureValue.string('hi'),
        'count': const MLFeatureValue.int64(4),
        'scale': const MLFeatureValue.float64(0.5),
        'words': MLDictionaryValue.strings({'a': 1}),
        'ids': MLDictionaryValue.int64s({7: 2}),
        'tokens': MLSequenceValue.int64s([1, 2]),
        'names': MLSequenceValue.strings(['x']),
        'optional': const MLUndefinedValue(MLFeatureType.image),
      });
      final inputs = host.lastPrediction!.inputs;
      expect(host.lastPrediction!.stateHandle, isNull);
      expect(inputs['array'], isA<MultiArrayMessage>());
      expect((inputs['file']! as EncodedImageMessage).path, '/a.png');
      expect((inputs['bytes']! as EncodedImageMessage).bytes, [9]);
      expect(inputs['pixels'], isA<PixelBufferMessage>());
      expect((inputs['text']! as StringValueMessage).value, 'hi');
      expect((inputs['count']! as Int64ValueMessage).value, 4);
      expect((inputs['scale']! as DoubleValueMessage).value, 0.5);
      expect((inputs['words']! as DictionaryValueMessage).stringKeyed, {
        'a': 1,
      });
      expect((inputs['ids']! as DictionaryValueMessage).int64Keyed, {7: 2});
      expect((inputs['tokens']! as SequenceValueMessage).int64s, [1, 2]);
      expect((inputs['names']! as SequenceValueMessage).strings, ['x']);
      expect(
        (inputs['optional']! as UndefinedValueMessage).featureType,
        FeatureTypeMessage.image,
      );
      await model.dispose();
    });

    test('maps every output kind from a message', () async {
      host.outputs = {
        'y': MLMultiArray.float16([1, 2]).toMessage(),
        'image': PixelBufferMessage(
          width: 1,
          height: 1,
          pixelFormatType: PixelFormat.bgra32,
          planes: [
            PixelBufferPlaneMessage(
              width: 1,
              height: 1,
              bytesPerRow: 4,
              data: Uint8List.fromList([1, 2, 3, 4]),
            ),
          ],
        ),
        'label': StringValueMessage(value: 'cat'),
        'count': Int64ValueMessage(value: 3),
        'score': DoubleValueMessage(value: 0.25),
        'probs': DictionaryValueMessage(stringKeyed: {'cat': 0.9}),
        'byId': DictionaryValueMessage(int64Keyed: {1: 0.1}),
        'tokens': SequenceValueMessage(int64s: [5]),
        'missing': UndefinedValueMessage(featureType: FeatureTypeMessage.int64),
      };
      final model = await MLModel.load('/m.mlmodelc');
      final prediction = await model.predict({});
      expect(prediction.multiArray('y').toDoubleList(), [1, 2]);
      expect(prediction.image('image').planes.single.bytes, [1, 2, 3, 4]);
      expect(prediction.stringValue('label'), 'cat');
      expect(prediction.int64Value('count'), 3);
      expect(prediction.doubleValue('score'), 0.25);
      expect(prediction.dictionary('probs').values, {'cat': 0.9});
      expect(prediction.dictionary('byId').int64Keyed, {1: 0.1});
      expect(prediction.sequence('tokens').int64s, [5]);
      expect(
        prediction['missing'],
        const MLUndefinedValue(MLFeatureType.int64),
      );
      expect(() => prediction.multiArray('nope'), throwsStateError);
      expect(() => prediction.stringValue('y'), throwsStateError);
      await model.dispose();
    });

    test('batch predictions keep their order', () async {
      final model = await MLModel.load('/m.mlmodelc');
      final results = await model.predictBatch([
        {'x': const MLFeatureValue.int64(1)},
        {'x': const MLFeatureValue.int64(2)},
      ]);
      expect(host.lastBatch!.inputs, hasLength(2));
      expect(results.map((r) => r.int64Value('i')), [0, 1]);
      await model.dispose();
    });

    test('stateful models need a state', () async {
      host.description = _description(
        states: [
          FeatureDescriptionMessage(
            name: 'total',
            type: FeatureTypeMessage.state,
            optional: false,
            stateConstraint: StateConstraintMessage(
              dataType: MultiArrayDataTypeMessage.float16,
              bufferShape: [3],
            ),
          ),
        ],
      );
      final model = await MLModel.load('/m.mlmodelc');
      expect(model.modelDescription.isStateful, isTrue);
      expect(
        model.modelDescription.states['total']!.stateConstraint!.bufferShape,
        [3],
      );
      await expectLater(
        model.predict({}),
        throwsCoreML(CoreMLErrorCode.invalidArgument),
      );

      final state = await model.makeState();
      expect(state.stateNames, ['total']);
      await model.predict({}, state: state);
      expect(host.lastPrediction!.stateHandle, state.handle);

      expect((await state.read('total')).toDoubleList(), [1, 2, 3]);
      await state.write('total', MLMultiArray.float16([4, 5, 6]));
      expect(host.writtenState!.dataType, MultiArrayDataTypeMessage.float16);
      await state.dispose();
      await model.dispose();
    });
  });

  group('errors', () {
    test('translates platform exceptions', () async {
      host.error = PlatformException(
        code: 'feature_type',
        message: 'wrong type',
        details: 'MLModelError(1)',
      );
      await expectLater(
        MLModel.load('/m.mlmodelc'),
        throwsA(
          isA<CoreMLException>()
              .having((e) => e.code, 'code', CoreMLErrorCode.featureType)
              .having((e) => e.message, 'message', 'wrong type')
              .having((e) => e.details, 'details', 'MLModelError(1)'),
        ),
      );
      host.error = PlatformException(code: 'something_new');
      await expectLater(
        MLModel.compile('/m.mlpackage'),
        throwsCoreML(CoreMLErrorCode.unknown),
      );
    });

    test('a missing host API means unsupported', () async {
      host.error = PlatformException(
        code: 'channel-error',
        message: 'Unable to establish connection on channel.',
      );
      await expectLater(
        MLModel.load('/m.mlmodelc'),
        throwsCoreML(CoreMLErrorCode.unsupported),
      );
    });

    test('every Swift error code has a Dart counterpart', () {
      const swiftCodes = [
        'unsupported',
        'invalid_handle',
        'invalid_argument',
        'not_found',
        'busy',
        'feature_type',
        'io_error',
        'model_decryption',
        'prediction_cancelled',
        'custom_model',
        'update_error',
        'parameters',
        'core_ml_error',
        'pixel_buffer_error',
      ];
      for (final code in swiftCodes) {
        final error = CoreMLException.fromPlatformException(
          PlatformException(code: code),
        );
        expect(error.code, isNot(CoreMLErrorCode.unknown), reason: code);
        expect(error.code.wireName, code);
      }
    });
  });

  group('disposal', () {
    test('releases once and rejects later use', () async {
      final model = await MLModel.load('/m.mlmodelc');
      final handle = model.handle;
      await model.dispose();
      await model.dispose();
      expect(host.released, [handle]);
      expect(model.isDisposed, isTrue);
      expect(() => model.handle, throwsStateError);
      expect(() => model.predict({}), throwsStateError);
      expect(model.makeState, throwsStateError);
    });

    test('states release their own handle', () async {
      final model = await MLModel.load('/m.mlmodelc');
      final state = await model.makeState();
      final handle = state.handle;
      await state.dispose();
      expect(host.released, [handle]);
      await model.dispose();
    });
  });
}

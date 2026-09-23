import 'package:core_ai/core_ai.dart';
import 'package:core_ai/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake Core AI host: one affine function `main(x) -> y` and a stateful
/// function `step(x, state total) -> y`.
class FakeHost implements CoreAIHostApi {
  final released = <int>[];
  final runs = <RunRequestMessage>[];
  final encodes = <EncodeRequestMessage>[];
  PlatformException? nextError;
  var _nextHandle = 100;

  int _handle() => _nextHandle++;

  void _maybeThrow() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  static final _x = ValueDescriptorMessage(
    name: 'x',
    kind: ValueKindMessage.ndArray,
    ndArray: NDArrayDescriptorMessage(
      scalarType: ScalarTypeMessage.float32,
      shape: [3],
      hasDynamicShape: false,
      preferredStrides: [1],
      minimumByteCount: 12,
    ),
  );

  static final _total = ValueDescriptorMessage(
    name: 'total',
    kind: ValueKindMessage.ndArray,
    ndArray: NDArrayDescriptorMessage(
      scalarType: ScalarTypeMessage.float32,
      shape: [-1],
      hasDynamicShape: true,
    ),
  );

  static FunctionDescriptorMessage descriptor(String name) =>
      FunctionDescriptorMessage(
        name: name,
        inputs: [_x],
        states: name == 'step' ? [_total] : [],
        outputs: [
          ValueDescriptorMessage(
            name: 'y',
            kind: ValueKindMessage.ndArray,
            ndArray: _x.ndArray,
          ),
        ],
      );

  @override
  Future<ModelInfoMessage> loadModel(
    String path,
    SpecializationOptionsMessage options,
  ) async {
    _maybeThrow();
    lastOptions = options;
    return ModelInfoMessage(handle: _handle(), functionNames: ['main', 'step']);
  }

  SpecializationOptionsMessage? lastOptions;

  @override
  Future<FunctionDescriptorMessage?> functionDescriptor(
    int modelHandle,
    String functionName,
  ) async => functionName == 'missing' ? null : descriptor(functionName);

  @override
  Future<FunctionInfoMessage?> loadFunction(
    int modelHandle,
    String functionName,
  ) async {
    if (functionName == 'missing') return null;
    return FunctionInfoMessage(
      handle: _handle(),
      descriptor: descriptor(functionName),
    );
  }

  @override
  Future<RunResultMessage> run(RunRequestMessage request) async {
    _maybeThrow();
    runs.add(request);
    return RunResultMessage(
      outputs: {
        'y': request.retainedOutputs.contains('y') || request.retainAllOutputs
            ? NativeValueRefMessage(handle: _handle())
            : NDArray.float32([3, 5, 7]).toMessage(),
      },
    );
  }

  @override
  Future<Map<String, int>> encode(EncodeRequestMessage request) async {
    encodes.add(request);
    return {'y': _handle()};
  }

  @override
  Future<int> createComputeStream() async => _handle();

  @override
  Future<int> allocateForDescriptor(
    int ownerHandle,
    String functionName,
    ValueRoleMessage role,
    String valueName,
    List<int>? shape,
    int? width,
    int? height,
  ) async {
    allocations.add((valueName, role, shape));
    return _handle();
  }

  final allocations = <(String, ValueRoleMessage, List<int>?)>[];

  @override
  Future<int> createNDArray(NDArrayMessage array) async => _handle();

  @override
  Future<ValueMessage> readValue(int handle) async =>
      NDArray.float32([1, 2, 3]).toMessage();

  @override
  Future<void> release(int handle) async => released.add(handle);

  @override
  Future<SpecializationInfoMessage> describeSpecializationOptions(
    SpecializationOptionsMessage options,
  ) async => SpecializationInfoMessage(
    allowedComputeUnitKinds: [ComputeUnitKindMessage.cpu],
    preferredComputeUnitKind: options.preferredComputeUnitKind,
    expectFrequentReshapes: options.expectFrequentReshapes,
  );

  @override
  Future<AssetMetadataMessage> assetMetadata(String path) async =>
      AssetMetadataMessage(
        author: 'A',
        license: 'L',
        modelDescription: 'D',
        creationDateMillis: 0,
        creatorDefined: {'k': 1},
      );

  AssetMetadataUpdateMessage? lastUpdate;

  @override
  Future<void> updateAssetMetadata(
    String path,
    AssetMetadataUpdateMessage update,
  ) async => lastUpdate = update;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeHost: ${invocation.memberName}');
}

class FakePlatform implements CoreAIPlatformApi {
  FakePlatform({this.supported = true});

  final bool supported;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<String?> assetPath(String assetKey, String? package) async =>
      assetKey == 'assets/m.aimodel' ? '/bundle/assets/m.aimodel' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlatform: ${invocation.memberName}');
}

void main() {
  late FakeHost host;

  setUp(() {
    host = FakeHost();
    CoreAIBindings.instance = CoreAIBindings(
      host: host,
      platform: FakePlatform(),
    );
  });

  Future<InferenceFunction> load(String name) async {
    final model = await AIModel.load('/m.aimodel');
    return model.loadFunction(name);
  }

  test('loads models with specialization options', () async {
    final model = await AIModel.load(
      '/m.aimodel',
      options: const SpecializationOptions.preferring(
        ComputeUnitKind.neuralEngine,
        expectFrequentReshapes: true,
      ),
    );
    expect(model.functionNames, ['main', 'step']);
    expect(host.lastOptions!.preset, SpecializationPresetMessage.preferred);
    expect(
      host.lastOptions!.preferredComputeUnitKind,
      ComputeUnitKindMessage.neuralEngine,
    );
    expect(host.lastOptions!.expectFrequentReshapes, isTrue);

    await AIModel.load('/m.aimodel', options: SpecializationOptions.cpuOnly);
    expect(host.lastOptions!.preset, SpecializationPresetMessage.cpuOnly);
  });

  test('resolves bundled assets', () async {
    final model = await AIModel.loadAsset('assets/m.aimodel/');
    expect(model.functionNames, isNotEmpty);
    await expectLater(
      AIModel.loadAsset('assets/other.aimodel'),
      throwsA(
        isA<CoreAIException>().having(
          (e) => e.code,
          'code',
          CoreAIErrorCode.notFound,
        ),
      ),
    );
  });

  test('describes functions', () async {
    final model = await AIModel.load('/m.aimodel');
    final descriptor = (await model.functionDescriptor('step'))!;
    expect(descriptor.inputs.keys, ['x']);
    expect(descriptor.isStateful, isTrue);
    final total = descriptor.states['total']! as NDArrayDescriptor;
    expect(total.hasDynamicShape, isTrue);
    expect(total.preferredStrides, isNull);
    expect(total.toString(), contains('[?]'));
    expect(await model.functionDescriptor('missing'), isNull);
    expect(
      () => model.loadFunction(),
      throwsArgumentError,
      reason: 'two functions need a name',
    );
    await expectLater(
      model.loadFunction('missing'),
      throwsA(isA<CoreAIException>()),
    );
  });

  test('marshals run requests', () async {
    final function = await load('main');
    final native = await NativeValue.fromNDArray(NDArray.float32([1, 2, 3]));
    final outputs = await function.run(
      {
        'x': NDArray.float32([1, 2, 3]),
        'native': native,
      },
      outputViews: {'view': native},
      retain: {'y'},
    );
    final request = host.runs.single;
    expect(request.functionHandle, function.handle);
    expect(request.inputs['x'], isA<NDArrayMessage>());
    expect(
      (request.inputs['native']! as NativeValueRefMessage).handle,
      native.handle,
    );
    expect(request.outputViews, {'view': native.handle});
    expect(request.retainedOutputs, ['y']);
    expect(outputs['y'], isA<NativeValue>());
    expect(() => outputs.ndArray('y'), throwsStateError);
    expect(() => outputs.ndArray('z'), throwsStateError);
  });

  test('returns copied outputs as NDArrays', () async {
    final function = await load('main');
    final outputs = await function.run({
      'x': NDArray.float32([1, 2, 3]),
    });
    expect(outputs.ndArray('y').toDoubleList(), [3, 5, 7]);
    switch (outputs['y']) {
      case NDArray array:
        expect(array.shape, [3]);
      case PixelBuffer() || NativeValue() || null:
        fail('expected an NDArray');
    }
  });

  test('requires every state', () async {
    final function = await load('step');
    await expectLater(
      function.run({
        'x': NDArray.float32([1, 2, 3]),
      }),
      throwsA(
        isA<CoreAIException>().having(
          (e) => e.code,
          'code',
          CoreAIErrorCode.invalidArgument,
        ),
      ),
    );
    expect(host.runs, isEmpty);

    final state = await function.makeState(
      shapes: {
        'total': [3],
      },
    );
    final (name, role, shape) = host.allocations.single;
    expect((name, role), ('total', ValueRoleMessage.state));
    expect(shape, [3]);
    await function.run({
      'x': NDArray.float32([1, 2, 3]),
    }, state: state);
    expect(host.runs.single.states, {'total': state['total'].handle});
  });

  test('encodes onto compute streams', () async {
    final function = await load('main');
    final stream = await ComputeStream.create();
    final outputs = await function.encode({
      'x': NDArray.float32([1, 2, 3]),
    }, stream: stream);
    expect(host.encodes.single.streamHandle, stream.handle);
    expect(outputs['y'], isA<NativeValue>());
    final chained = await function.encode({'x': outputs['y']!}, stream: stream);
    expect(host.encodes.last.inputs['x'], isA<NativeValueRefMessage>());
    expect(chained.keys, ['y']);
  });

  test('maps platform errors', () async {
    host.nextError = PlatformException(
      code: 'core_ai_error',
      message: 'boom',
      details: 'Swift detail',
    );
    await expectLater(
      AIModel.load('/m.aimodel'),
      throwsA(
        isA<CoreAIException>()
            .having((e) => e.code, 'code', CoreAIErrorCode.coreAIError)
            .having((e) => e.message, 'message', 'boom')
            .having((e) => e.details, 'details', 'Swift detail'),
      ),
    );

    host.nextError = PlatformException(code: 'channel-error');
    await expectLater(
      AIModel.load('/m.aimodel'),
      throwsA(
        isA<CoreAIException>().having(
          (e) => e.code,
          'code',
          CoreAIErrorCode.unsupported,
        ),
      ),
    );

    host.nextError = PlatformException(code: 'something_new');
    await expectLater(
      AIModel.load('/m.aimodel'),
      throwsA(
        isA<CoreAIException>().having(
          (e) => e.code,
          'code',
          CoreAIErrorCode.unknown,
        ),
      ),
    );
  });

  test('disposes once and rejects later use', () async {
    final function = await load('main');
    final handle = function.handle;
    await function.dispose();
    await function.dispose();
    expect(host.released, [handle]);
    expect(function.isDisposed, isTrue);
    expect(() => function.handle, throwsStateError);
    expect(
      () => function.run({
        'x': NDArray.float32([1, 2, 3]),
      }),
      throwsStateError,
    );
  });

  test('value types compare by value', () {
    expect(
      const SpecializationOptions.preferring(ComputeUnitKind.gpu),
      const SpecializationOptions.preferring(ComputeUnitKind.gpu),
    );
    expect(
      SpecializationOptions.defaults.copyWith(expectFrequentReshapes: true),
      isNot(SpecializationOptions.defaults),
    );
    expect(CachePolicy.defaults, const CachePolicy());
    expect(CachePolicy.persistent.toMessage().purgeOnStoragePressure, isFalse);
    expect(
      const AIModelCache.appGroup('g').toMessage().appGroupIdentifier,
      'g',
    );
    expect(AIModelCache.shared.toMessage().appGroupIdentifier, isNull);
  });

  test('resolves specialization info', () async {
    final info = await const SpecializationOptions.preferring(
      ComputeUnitKind.gpu,
    ).resolve();
    expect(info.allowedComputeUnitKinds, {ComputeUnitKind.cpu});
    expect(info.preferredComputeUnitKind, ComputeUnitKind.gpu);
  });

  test('reads and updates asset metadata', () async {
    final asset = const AIModelAsset('/m.aimodel');
    final metadata = await asset.metadata();
    expect(metadata.author, 'A');
    expect(metadata.creationDate, DateTime.utc(1970));
    expect(metadata.creatorDefined, {'k': 1});

    await asset.updateMetadata(
      description: 'new',
      creationDate: DateTime.utc(2026),
      creatorDefined: {'n': 2.5},
      removeCreatorDefined: ['k'],
    );
    final update = host.lastUpdate!;
    expect(update.modelDescription, 'new');
    expect(update.author, isNull);
    expect(
      update.creationDateMillis,
      DateTime.utc(2026).millisecondsSinceEpoch,
    );
    expect(update.creatorDefinedRemovals, ['k']);
  });

  test('reports unsupported platforms', () async {
    CoreAIBindings.instance = CoreAIBindings(
      host: host,
      platform: FakePlatform(supported: false),
    );
    expect(await CoreAI.isSupported(), isFalse);
  });

  test('native values read back', () async {
    final value = await NativeValue.fromNDArray(NDArray.float32([1, 2, 3]));
    expect((await value.readNDArray()).toDoubleList(), [1, 2, 3]);
    await expectLater(value.readPixelBuffer(), throwsA(isA<CoreAIException>()));
  });
}

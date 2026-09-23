import 'dart:collection';

import 'bindings.dart';
import 'configuration.dart';
import 'description.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'native_resource.dart';
import 'values.dart';

/// A loaded Core ML model (`MLModel`).
///
/// Core ML loads compiled models (`.mlmodelc` directories). Compile a
/// `.mlmodel` or `.mlpackage` first with [compile], or use [compileAndLoad]
/// or [loadAsset], which do it for you.
///
/// ```dart
/// final model = await MLModel.loadAsset('assets/models/affine.mlpackage');
/// final prediction = await model.predict({
///   'x': MLMultiArray.float32([1, 2, 3]),
/// });
/// print(prediction.multiArray('y').toDoubleList()); // [3, 5, 7]
/// await model.dispose();
/// ```
///
/// A model may predict from several callers at once.
final class MLModel extends NativeResource {
  MLModel._(ModelInfoMessage info)
    : modelDescription = MLModelDescription.fromMessage(info.modelDescription),
      configuration = MLModelConfiguration.fromMessage(info.configuration),
      super(info.handle);

  /// Compiles the `.mlmodel` or `.mlpackage` at [path] for this device
  /// (`MLModel.compileModel(at:)`) and returns the `.mlmodelc` path.
  ///
  /// Core ML compiles into a temporary directory that the system may delete.
  /// Pass [destination] (a path ending in `.mlmodelc`, typically in the
  /// application support directory) to move the result somewhere permanent
  /// and skip compiling on later launches. Anything already at
  /// [destination] is replaced.
  static Future<String> compile(String path, {String? destination}) {
    final host = CoreMLBindings.instance.host;
    return guardPlatformCall(() => host.compileModel(path, destination));
  }

  /// Loads the compiled model (`.mlmodelc`) at [compiledPath]
  /// (`MLModel.load(contentsOf:configuration:)`).
  static Future<MLModel> load(
    String compiledPath, {
    MLModelConfiguration configuration = const MLModelConfiguration(),
  }) async {
    final host = CoreMLBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.loadModel(compiledPath, configuration.toMessage()),
    );
    return MLModel._(info);
  }

  /// Compiles [path] (see [compile]) and loads the result.
  ///
  /// A `.mlmodelc` is loaded directly.
  static Future<MLModel> compileAndLoad(
    String path, {
    MLModelConfiguration configuration = const MLModelConfiguration(),
    String? compiledDestination,
  }) async {
    final compiled = _isCompiled(path)
        ? path
        : await compile(path, destination: compiledDestination);
    return load(compiled, configuration: configuration);
  }

  /// Loads a model bundled as a Flutter asset, compiling it first unless it
  /// is already a `.mlmodelc`.
  ///
  /// `.mlpackage` and `.mlmodelc` are directory trees, and Flutter's asset
  /// directory entries are not recursive, so list every directory of the
  /// model that holds files under `flutter: assets:` (for example
  /// `assets/Model.mlpackage/` and
  /// `assets/Model.mlpackage/Data/com.apple.CoreML/`).
  static Future<MLModel> loadAsset(
    String assetKey, {
    String? package,
    MLModelConfiguration configuration = const MLModelConfiguration(),
    String? compiledDestination,
  }) async {
    final path = await resolveAssetPath(assetKey, package: package);
    return compileAndLoad(
      path,
      configuration: configuration,
      compiledDestination: compiledDestination,
    );
  }

  /// The function names of a compiled multi-function model
  /// (`MLModelAsset.functionNames`). Select one with
  /// [MLModelConfiguration.functionName].
  static Future<List<String>> functionNames(String compiledPath) {
    final host = CoreMLBindings.instance.host;
    return guardPlatformCall(() => host.functionNames(compiledPath));
  }

  /// The description of a compiled model without loading it
  /// (`MLModelAsset.modelDescription`), optionally of one function.
  static Future<MLModelDescription> describe(
    String compiledPath, {
    String? functionName,
  }) async {
    final host = CoreMLBindings.instance.host;
    final message = await guardPlatformCall(
      () => host.assetModelDescription(compiledPath, functionName),
    );
    return MLModelDescription.fromMessage(message);
  }

  /// The model's inputs, outputs, states and metadata.
  final MLModelDescription modelDescription;

  /// The configuration Core ML loaded the model with.
  final MLModelConfiguration configuration;

  /// Runs a prediction (`MLModel.prediction(from:options:)`, Core ML's async
  /// API).
  ///
  /// Every non-optional input of [modelDescription] must be present. A
  /// stateful model also needs a [state] from [makeState]; the prediction
  /// reads and updates it (`prediction(from:using:options:)`).
  Future<MLPrediction> predict(
    Map<String, MLFeatureValue> inputs, {
    MLState? state,
  }) async {
    if (state == null && modelDescription.isStateful) {
      throw CoreMLException(
        CoreMLErrorCode.invalidArgument,
        'This model has states ${modelDescription.states.keys.toList()}; '
        'pass a state from makeState().',
      );
    }
    final result = await guardPlatformCall(
      () => bindings.host.predict(
        PredictionRequestMessage(
          modelHandle: handle,
          inputs: _messages(inputs),
          stateHandle: state?.handle,
        ),
      ),
    );
    return MLPrediction._fromMessages(result.outputs);
  }

  /// Runs predictions for several inputs in one call
  /// (`MLModel.predictions(from:options:)`), which lets Core ML batch the
  /// work. Results are in the order of [inputs].
  Future<List<MLPrediction>> predictBatch(
    List<Map<String, MLFeatureValue>> inputs,
  ) async {
    final result = await guardPlatformCall(
      () => bindings.host.predictBatch(
        BatchPredictionRequestMessage(
          modelHandle: handle,
          inputs: [
            for (final features in inputs)
              FeatureMapMessage(features: _messages(features)),
          ],
        ),
      ),
    );
    return [
      for (final output in result.outputs)
        MLPrediction._fromMessages(output.features),
    ];
  }

  /// Creates zero-filled state buffers for a stateful model
  /// (`MLModel.makeState()`).
  ///
  /// A stateless model returns an empty state, which predictions accept.
  Future<MLState> makeState() async {
    final stateHandle = await guardPlatformCall(
      () => bindings.host.makeState(handle),
    );
    return MLState._(stateHandle, modelDescription.states.keys.toList());
  }

  static Map<String, FeatureValueMessage> _messages(
    Map<String, MLFeatureValue> values,
  ) => values.map((name, value) => MapEntry(name, value.toMessage()));

  static bool _isCompiled(String path) {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return trimmed.endsWith('.mlmodelc');
  }

  @override
  String toString() => 'MLModel($modelDescription)';
}

/// The state buffers of a stateful model (`MLState`), from
/// [MLModel.makeState].
///
/// Pass it to each [MLModel.predict] of a sequence; Core ML updates it in
/// place. Core ML requires predictions that share a state to run one at a
/// time, so overlapping use fails with [CoreMLErrorCode.busy].
final class MLState extends NativeResource {
  MLState._(super.handle, List<String> names)
    : stateNames = List.unmodifiable(names);

  /// The names of the state buffers.
  final List<String> stateNames;

  /// Copies state buffer [name] into Dart (`MLState.withMultiArray(for:)`).
  Future<MLMultiArray> read(String name) async {
    final message = await guardPlatformCall(
      () => bindings.host.readState(handle, name),
    );
    return MLMultiArray.fromMessage(message);
  }

  /// Overwrites state buffer [name]. [array] must have the buffer's data type
  /// and shape.
  Future<void> write(String name, MLMultiArray array) => guardPlatformCall(
    () => bindings.host.writeState(handle, name, array.toMessage()),
  );

  @override
  String toString() => 'MLState($stateNames)';
}

/// The outputs of a prediction, keyed by feature name.
final class MLPrediction extends UnmodifiableMapBase<String, MLFeatureValue> {
  MLPrediction._(this._values);

  MLPrediction._fromMessages(Map<String, FeatureValueMessage> messages)
    : this._({
        for (final entry in messages.entries)
          entry.key: featureValueFromMessage(entry.value),
      });

  final Map<String, MLFeatureValue> _values;

  @override
  MLFeatureValue? operator [](Object? key) => _values[key];

  @override
  Iterable<String> get keys => _values.keys;

  /// Output [name] as an [MLMultiArray].
  MLMultiArray multiArray(String name) => _typed<MLMultiArray>(name);

  /// Output [name] as a [PixelBuffer].
  PixelBuffer image(String name) => _typed<PixelBuffer>(name);

  /// Output [name] as a string.
  String stringValue(String name) => _typed<MLStringValue>(name).value;

  /// Output [name] as an int64.
  int int64Value(String name) => _typed<MLInt64Value>(name).value;

  /// Output [name] as a double.
  double doubleValue(String name) => _typed<MLDoubleValue>(name).value;

  /// Output [name] as a dictionary.
  MLDictionaryValue dictionary(String name) => _typed<MLDictionaryValue>(name);

  /// Output [name] as a sequence.
  MLSequenceValue sequence(String name) => _typed<MLSequenceValue>(name);

  T _typed<T extends MLFeatureValue>(String name) {
    final value = _values[name];
    if (value is T) return value;
    throw StateError(
      value == null
          ? 'No output named "$name". Outputs: ${_values.keys.toList()}.'
          : 'Output "$name" is a ${value.runtimeType}, not a $T.',
    );
  }
}

/// The on-disk path of a bundled Flutter asset, such as a `.mlpackage`
/// directory.
Future<String> resolveAssetPath(String assetKey, {String? package}) async {
  final platform = CoreMLBindings.instance.platform;
  final key = assetKey.endsWith('/')
      ? assetKey.substring(0, assetKey.length - 1)
      : assetKey;
  final path = await guardPlatformCall(() => platform.assetPath(key, package));
  if (path == null) {
    throw CoreMLException(
      CoreMLErrorCode.notFound,
      'Asset "$key" is not in the app bundle. List the model directory (and '
      'each subdirectory that holds files) under flutter: assets: in '
      'pubspec.yaml.',
    );
  }
  return path;
}

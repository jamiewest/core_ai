import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'descriptors.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'native_resource.dart';
import 'specialization.dart';
import 'values.dart';

/// A model specialized for this device (Core AI's `AIModel`).
///
/// ```dart
/// final model = await AIModel.load('/path/to/Model.aimodel');
/// final function = await model.loadFunction('main');
/// final outputs = await function.run({'x': NDArray.float32([1, 2, 3])});
/// print(outputs.ndArray('y').toDoubleList());
/// await function.dispose();
/// await model.dispose();
/// ```
///
/// The model is lightweight: weights and buffers belong to the functions
/// loaded from it, which stay usable after the model is disposed.
final class AIModel extends NativeResource {
  AIModel._(ModelInfoMessage info)
    : functionNames = List.unmodifiable(info.functionNames),
      super(info.handle);

  /// Loads the `.aimodel` (or `.aimodelc`) at [path], specializing it first
  /// if the default cache has no matching entry.
  ///
  /// Specialization can take a long time for large models; later loads with
  /// the same [options] reuse the cached result.
  static Future<AIModel> load(
    String path, {
    SpecializationOptions options = SpecializationOptions.defaults,
  }) async {
    final host = CoreAIBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.loadModel(path, options.toMessage()),
    );
    return AIModel._(info);
  }

  /// Loads a model bundled as a Flutter asset.
  ///
  /// An `.aimodel` is a directory, so list the directory itself under
  /// `flutter: assets:` (for example `- assets/Model.aimodel/`) and pass its
  /// path without the trailing slash as [assetKey].
  static Future<AIModel> loadAsset(
    String assetKey, {
    String? package,
    SpecializationOptions options = SpecializationOptions.defaults,
  }) async {
    final path = await resolveAssetPath(assetKey, package: package);
    return load(path, options: options);
  }

  /// Specializes the model at [path] into [cache] with [policy], then loads
  /// it (Core AI's `AIModel.specialize`).
  static Future<AIModel> specialize(
    String path, {
    SpecializationOptions options = SpecializationOptions.defaults,
    AIModelCache cache = AIModelCache.shared,
    CachePolicy policy = CachePolicy.defaults,
  }) async {
    final host = CoreAIBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.specializeModel(
        path,
        options.toMessage(),
        cache.toMessage(),
        policy.toMessage(),
      ),
    );
    return AIModel._(info);
  }

  /// Re-creates a model from [bookmarkData], or returns null if the cache
  /// entry it points to no longer exists.
  static Future<AIModel?> fromBookmark(Uint8List bookmark) async {
    final host = CoreAIBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.modelFromBookmark(bookmark),
    );
    return info == null ? null : AIModel._(info);
  }

  /// The names of the model's inference functions.
  final List<String> functionNames;

  /// Serialized data identifying this model's cache entry, for
  /// [fromBookmark] and [AIModelCache.deleteEntryForBookmark].
  ///
  /// A bookmark does not keep the entry from being purged.
  Future<Uint8List> bookmarkData() =>
      guardPlatformCall(() => bindings.host.modelBookmarkData(handle));

  /// The signature of function [name], or null if there is none.
  Future<FunctionDescriptor?> functionDescriptor(String name) async {
    final message = await guardPlatformCall(
      () => bindings.host.functionDescriptor(handle, name),
    );
    return message == null ? null : FunctionDescriptor.fromMessage(message);
  }

  /// Loads function [name], which allocates its weights and buffers.
  ///
  /// [name] may be omitted when the model has exactly one function. Throws a
  /// [CoreAIException] with [CoreAIErrorCode.notFound] if there is no such
  /// function.
  Future<InferenceFunction> loadFunction([String? name]) async {
    final functionName = name ?? _onlyFunctionName();
    final info = await guardPlatformCall(
      () => bindings.host.loadFunction(handle, functionName),
    );
    if (info == null) {
      throw CoreAIException(
        CoreAIErrorCode.notFound,
        'The model has no function named "$functionName". Available: '
        '$functionNames.',
      );
    }
    return InferenceFunction._(info);
  }

  /// The descriptor of an argument of [functionName] with its dynamic
  /// dimensions replaced by [shape].
  Future<NDArrayDescriptor> resolveDynamicDimensions(
    String functionName,
    String valueName,
    List<int> shape, {
    ValueRole role = ValueRole.input,
  }) async {
    final message = await guardPlatformCall(
      () => bindings.host.resolveDynamicDimensions(
        handle,
        functionName,
        role.toMessage(),
        valueName,
        shape,
      ),
    );
    return NDArrayDescriptor.fromMessage(valueName, message);
  }

  String _onlyFunctionName() {
    if (functionNames.length == 1) return functionNames.single;
    throw ArgumentError(
      'The model has ${functionNames.length} functions ($functionNames); '
      'pass a name.',
    );
  }

  @override
  String toString() => 'AIModel(functions: $functionNames)';
}

/// The on-disk path of a bundled Flutter asset, such as an `.aimodel`
/// directory.
Future<String> resolveAssetPath(String assetKey, {String? package}) async {
  final platform = CoreAIBindings.instance.platform;
  final key = assetKey.endsWith('/')
      ? assetKey.substring(0, assetKey.length - 1)
      : assetKey;
  final path = await guardPlatformCall(() => platform.assetPath(key, package));
  if (path == null) {
    throw CoreAIException(
      CoreAIErrorCode.notFound,
      'Asset "$key" is not in the app bundle. List the .aimodel directory '
      'under flutter: assets: in pubspec.yaml.',
    );
  }
  return path;
}

/// A cache of specialized models (Core AI's `AIModelCache`).
@immutable
final class AIModelCache {
  const AIModelCache._(this.appGroupIdentifier);

  /// The cache shared by every app in the app group [identifier], so they
  /// specialize a shared model only once. Needs the App Groups entitlement.
  const AIModelCache.appGroup(String identifier) : this._(identifier);

  /// The app's own cache, used by [AIModel.load].
  static const AIModelCache shared = AIModelCache._(null);

  /// The app group, or null for [shared].
  final String? appGroupIdentifier;

  /// Whether this cache can be used (an app-group cache needs a valid group
  /// and entitlement).
  Future<bool> isAvailable() {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(() => host.isCacheAvailable(toMessage()));
  }

  /// The previously specialized model at [path] for [options], or null.
  /// Never specializes.
  Future<AIModel?> model(
    String path, {
    SpecializationOptions options = SpecializationOptions.defaults,
  }) async {
    final host = CoreAIBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.cachedModel(path, options.toMessage(), toMessage()),
    );
    return info == null ? null : AIModel._(info);
  }

  /// Specializes [path] into this cache. See [AIModel.specialize].
  Future<AIModel> specialize(
    String path, {
    SpecializationOptions options = SpecializationOptions.defaults,
    CachePolicy policy = CachePolicy.defaults,
  }) => AIModel.specialize(path, options: options, cache: this, policy: policy);

  /// Deletes the entry for [path] and [options].
  ///
  /// Fails while an [AIModel] loaded from that entry is still alive.
  Future<void> deleteEntry(
    String path, {
    SpecializationOptions options = SpecializationOptions.defaults,
  }) {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(
      () => host.deleteCacheEntry(path, options.toMessage(), toMessage()),
    );
  }

  /// Deletes every entry for [path], whatever its options.
  Future<void> deleteEntries(String path) {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(() => host.deleteCacheEntries(path, toMessage()));
  }

  /// Deletes every entry in this cache.
  Future<void> deleteAll() {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(() => host.deleteAllCacheEntries(toMessage()));
  }

  /// Deletes the entry a bookmark from [AIModel.bookmarkData] refers to.
  static Future<void> deleteEntryForBookmark(Uint8List bookmark) {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(() => host.deleteCacheEntryForBookmark(bookmark));
  }

  /// The Pigeon representation.
  ModelCacheMessage toMessage() =>
      ModelCacheMessage(appGroupIdentifier: appGroupIdentifier);

  @override
  bool operator ==(Object other) =>
      other is AIModelCache && other.appGroupIdentifier == appGroupIdentifier;

  @override
  int get hashCode => appGroupIdentifier.hashCode;

  @override
  String toString() => appGroupIdentifier == null
      ? 'AIModelCache.shared'
      : 'AIModelCache.appGroup($appGroupIdentifier)';
}

/// A loaded inference function (Core AI's `InferenceFunction`).
///
/// A function may run concurrently from several callers; Core AI allocates
/// extra buffers as needed.
final class InferenceFunction extends NativeResource {
  InferenceFunction._(FunctionInfoMessage info)
    : descriptor = FunctionDescriptor.fromMessage(info.descriptor),
      super(info.handle);

  /// The function's signature.
  final FunctionDescriptor descriptor;

  /// The function name.
  String get name => descriptor.name;

  /// Runs the function (Core AI's `run(inputs:states:outputViews:)`).
  ///
  /// * [inputs] may be [NDArray]s, [PixelBuffer]s or [NativeValue]s.
  /// * Every state must be supplied, through [state] (from [makeState]) or
  ///   [states]. States are read and updated in place.
  /// * [outputViews] are pre-allocated outputs updated in place; they are
  ///   not included in the result.
  /// * Outputs named in [retain] (or all of them with [retainAll]) stay on
  ///   the native side and are returned as [NativeValue]s, which avoids
  ///   copying them when they feed another function. Other outputs are
  ///   copied into Dart as [NDArray]s or [PixelBuffer]s.
  Future<InferenceOutputs> run(
    Map<String, InferenceValue> inputs, {
    InferenceState? state,
    Map<String, NativeValue> states = const {},
    Map<String, NativeValue> outputViews = const {},
    Set<String> retain = const {},
    bool retainAll = false,
  }) async {
    final stateValues = _stateValues(state, states);
    final result = await guardPlatformCall(
      () => bindings.host.run(
        RunRequestMessage(
          functionHandle: handle,
          inputs: _inputMessages(inputs),
          states: _handles(stateValues),
          outputViews: _handles(outputViews),
          retainedOutputs: retain.toList(),
          retainAllOutputs: retainAll,
        ),
      ),
    );
    return InferenceOutputs._({
      for (final entry in result.outputs.entries)
        entry.key: valueFromMessage(entry.value),
    });
  }

  /// Encodes the function onto [stream] without waiting for it to finish
  /// (Core AI's `encode(inputs:states:outputViews:to:)`).
  ///
  /// Returns async [NativeValue]s for the outputs. Pass them as inputs to
  /// further `encode` calls to build a pipeline, then `read` them (which
  /// waits) or await [ComputeStream.completed]. States and output views are
  /// updated asynchronously and stay in use until the work finishes.
  Future<Map<String, NativeValue>> encode(
    Map<String, InferenceValue> inputs, {
    required ComputeStream stream,
    InferenceState? state,
    Map<String, NativeValue> states = const {},
    Map<String, NativeValue> outputViews = const {},
  }) async {
    final stateValues = _stateValues(state, states);
    final result = await guardPlatformCall(
      () => bindings.host.encode(
        EncodeRequestMessage(
          functionHandle: handle,
          streamHandle: stream.handle,
          inputs: _inputMessages(inputs),
          states: _handles(stateValues),
          outputViews: _handles(outputViews),
        ),
      ),
    );
    return {
      for (final entry in result.entries)
        entry.key: adoptNativeValue(entry.value),
    };
  }

  /// Allocates zero-filled native values for every state, using the layout
  /// the function prefers.
  ///
  /// States with dynamic shapes need an entry in [shapes]; image states with
  /// dynamic sizes need an entry in [imageSizes] (width, height).
  Future<InferenceState> makeState({
    Map<String, List<int>> shapes = const {},
    Map<String, (int, int)> imageSizes = const {},
  }) async {
    final values = <String, NativeValue>{};
    try {
      for (final name in descriptor.states.keys) {
        final size = imageSizes[name];
        values[name] = await allocate(
          name,
          role: ValueRole.state,
          shape: shapes[name],
          width: size?.$1,
          height: size?.$2,
        );
      }
    } catch (_) {
      await Future.wait(values.values.map((value) => value.dispose()));
      rethrow;
    }
    return InferenceState(values);
  }

  /// Allocates a zero-filled native value for argument [valueName] with the
  /// layout the function prefers (preferred strides and interleave, or a
  /// pixel buffer of the described size and format).
  ///
  /// Useful for [run]'s `outputViews` and for inputs that are refilled for
  /// every call.
  Future<NativeValue> allocate(
    String valueName, {
    ValueRole role = ValueRole.output,
    List<int>? shape,
    int? width,
    int? height,
  }) async {
    final valueHandle = await guardPlatformCall(
      () => bindings.host.allocateForDescriptor(
        handle,
        name,
        role.toMessage(),
        valueName,
        shape,
        width,
        height,
      ),
    );
    return adoptNativeValue(valueHandle);
  }

  /// The descriptor of argument [valueName] with its dynamic dimensions
  /// replaced by [shape].
  Future<NDArrayDescriptor> resolveDynamicDimensions(
    String valueName,
    List<int> shape, {
    ValueRole role = ValueRole.input,
  }) async {
    final message = await guardPlatformCall(
      () => bindings.host.resolveDynamicDimensions(
        handle,
        name,
        role.toMessage(),
        valueName,
        shape,
      ),
    );
    return NDArrayDescriptor.fromMessage(valueName, message);
  }

  Map<String, NativeValue> _stateValues(
    InferenceState? state,
    Map<String, NativeValue> states,
  ) {
    final all = {...?state?.values, ...states};
    final missing = descriptor.states.keys.where((n) => !all.containsKey(n));
    if (missing.isNotEmpty) {
      throw CoreAIException(
        CoreAIErrorCode.invalidArgument,
        'Function "$name" needs every state; missing ${missing.toList()}. '
        'Create them with makeState().',
      );
    }
    return all;
  }

  static Map<String, ValueMessage> _inputMessages(
    Map<String, InferenceValue> inputs,
  ) => inputs.map((name, value) => MapEntry(name, valueToMessage(value)));

  static Map<String, int> _handles(Map<String, NativeValue> values) =>
      values.map((name, value) => MapEntry(name, value.handle));

  @override
  String toString() => 'InferenceFunction($name)';
}

/// The native state values of a stateful function, from
/// [InferenceFunction.makeState].
///
/// Pass it to every [InferenceFunction.run] of a sequence (for example each
/// decoding step of a language model); the function updates it in place.
final class InferenceState {
  /// Wraps existing native values, keyed by state name.
  InferenceState(Map<String, NativeValue> values)
    : values = UnmodifiableMapView(values);

  /// The native value of each state.
  final Map<String, NativeValue> values;

  /// The native value of state [name].
  NativeValue operator [](String name) =>
      values[name] ??
      (throw ArgumentError.value(name, 'name', 'no such state'));

  /// Zero-fills every state, for example to start a new sequence.
  Future<void> reset() => Future.wait(values.values.map((v) => v.zero()));

  /// Copies every state into Dart.
  Future<Map<String, InferenceValue>> read() async => {
    for (final entry in values.entries) entry.key: await entry.value.read(),
  };

  /// Releases the native values.
  Future<void> dispose() => Future.wait(values.values.map((v) => v.dispose()));
}

/// The outputs of [InferenceFunction.run], keyed by output name.
final class InferenceOutputs
    extends UnmodifiableMapBase<String, InferenceValue> {
  InferenceOutputs._(this._values);

  final Map<String, InferenceValue> _values;

  @override
  InferenceValue? operator [](Object? key) => _values[key];

  @override
  Iterable<String> get keys => _values.keys;

  /// Output [name] as an [NDArray].
  NDArray ndArray(String name) => _typed<NDArray>(name);

  /// Output [name] as a [PixelBuffer].
  PixelBuffer pixelBuffer(String name) => _typed<PixelBuffer>(name);

  /// Output [name] as a retained [NativeValue].
  NativeValue nativeValue(String name) => _typed<NativeValue>(name);

  /// Disposes every retained [NativeValue] output.
  Future<void> disposeNativeValues() => Future.wait(
    _values.values.whereType<NativeValue>().map((value) => value.dispose()),
  );

  T _typed<T extends InferenceValue>(String name) {
    final value = _values[name];
    if (value is T) return value;
    throw StateError(
      value == null
          ? 'No output named "$name". Outputs: ${_values.keys.toList()}.'
          : 'Output "$name" is a ${value.runtimeType}, not a $T.',
    );
  }
}

/// A queue of asynchronously encoded inference work (Core AI's
/// `ComputeStream`). See [InferenceFunction.encode].
final class ComputeStream extends NativeResource {
  ComputeStream._(super.handle);

  /// Creates a stream with its own Metal command queue.
  static Future<ComputeStream> create() async {
    final host = CoreAIBindings.instance.host;
    return ComputeStream._(
      await guardPlatformCall(() => host.createComputeStream()),
    );
  }

  /// Completes when all work encoded so far has finished.
  Future<void> completed() =>
      guardPlatformCall(() => bindings.host.computeStreamCompleted(handle));

  @override
  String toString() => 'ComputeStream(${isDisposed ? 'disposed' : handle})';
}

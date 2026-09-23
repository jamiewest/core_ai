import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'messages.g.dart';
import 'scalar_type.dart';

/// Which argument list of an inference function a value belongs to.
enum ValueRole {
  /// A read-only input.
  input,

  /// An in-out argument the function reads and updates in place, such as a
  /// key-value cache.
  state,

  /// A produced value.
  output;

  /// The Pigeon representation.
  ValueRoleMessage toMessage() => ValueRoleMessage.values[index];
}

/// Describes an interleaved memory layout (Core AI's
/// `NDArray.InterleaveLayout`).
///
/// Elements of [dimension] are stored in contiguous blocks of [factor]
/// elements. The stride reported for [dimension] is then a block stride: the
/// element offset of index `i` along it is
/// `(i ~/ factor) * stride + (i % factor)`.
@immutable
final class InterleaveLayout {
  /// Creates a layout interleaving [dimension] by [factor].
  const InterleaveLayout({required this.dimension, required this.factor});

  /// Converts from the Pigeon representation.
  factory InterleaveLayout.fromMessage(InterleaveLayoutMessage message) =>
      InterleaveLayout(dimension: message.dimension, factor: message.factor);

  /// The interleaved dimension.
  final int dimension;

  /// How many elements of [dimension] are stored contiguously per block.
  final int factor;

  /// The Pigeon representation.
  InterleaveLayoutMessage toMessage() =>
      InterleaveLayoutMessage(dimension: dimension, factor: factor);

  @override
  bool operator ==(Object other) =>
      other is InterleaveLayout &&
      other.dimension == dimension &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(dimension, factor);

  @override
  String toString() =>
      'InterleaveLayout(dimension: $dimension, '
      'factor: $factor)';
}

/// The expected type and shape of one named function argument
/// (Core AI's `InferenceValue.Descriptor`).
sealed class ValueDescriptor {
  const ValueDescriptor(this.name);

  /// Converts from the Pigeon representation.
  factory ValueDescriptor.fromMessage(ValueDescriptorMessage message) {
    final ndArray = message.ndArray;
    final image = message.image;
    if (ndArray != null) {
      return NDArrayDescriptor.fromMessage(message.name, ndArray);
    }
    if (image != null) {
      return ImageDescriptor.fromMessage(message.name, image);
    }
    throw ArgumentError('Descriptor "${message.name}" has no payload.');
  }

  /// The argument name.
  final String name;
}

/// Describes an NDArray argument (Core AI's `NDArrayDescriptor`).
final class NDArrayDescriptor extends ValueDescriptor {
  /// Creates a descriptor.
  const NDArrayDescriptor({
    required String name,
    required this.scalarType,
    required this.shape,
    required this.hasDynamicShape,
    this.interleaveLayout,
    this.preferredStrides,
    this.minimumByteCount,
  }) : super(name);

  /// Converts from the Pigeon representation.
  factory NDArrayDescriptor.fromMessage(
    String name,
    NDArrayDescriptorMessage message,
  ) {
    final interleave = message.interleaveLayout;
    final strides = message.preferredStrides;
    return NDArrayDescriptor(
      name: name,
      scalarType: message.scalarType.toScalarType(),
      shape: List.unmodifiable(message.shape),
      hasDynamicShape: message.hasDynamicShape,
      interleaveLayout: interleave == null
          ? null
          : InterleaveLayout.fromMessage(interleave),
      preferredStrides: strides == null ? null : List.unmodifiable(strides),
      minimumByteCount: message.minimumByteCount,
    );
  }

  /// The required element type. Inputs must use exactly this type.
  final ScalarType scalarType;

  /// The length of each dimension; `-1` marks a dynamic dimension.
  final List<int> shape;

  /// Whether any dimension of [shape] is dynamic.
  final bool hasDynamicShape;

  /// The interleaved layout the function prefers, if any.
  final InterleaveLayout? interleaveLayout;

  /// The element strides that avoid a layout copy during inference.
  ///
  /// Null when [hasDynamicShape] is true; resolve the shape first with
  /// `InferenceFunction.resolveDynamicDimensions`.
  final List<int>? preferredStrides;

  /// The minimum storage size in bytes, when the shape is static.
  final int? minimumByteCount;

  /// The number of dimensions.
  int get rank => shape.length;

  @override
  String toString() {
    final dims = shape.map((d) => d < 0 ? '?' : '$d').join(', ');
    return 'NDArrayDescriptor($name: ${scalarType.name} [$dims])';
  }
}

/// Describes an image argument (Core AI's `ImageDescriptor`).
final class ImageDescriptor extends ValueDescriptor {
  /// Creates a descriptor.
  const ImageDescriptor({
    required String name,
    required this.width,
    required this.height,
    required this.pixelFormatType,
  }) : super(name);

  /// Converts from the Pigeon representation.
  factory ImageDescriptor.fromMessage(
    String name,
    ImageDescriptorMessage message,
  ) => ImageDescriptor(
    name: name,
    width: message.width,
    height: message.height,
    pixelFormatType: message.pixelFormatType,
  );

  /// Width in pixels; `-1` when dynamic.
  final int width;

  /// Height in pixels; `-1` when dynamic.
  final int height;

  /// The Core Video pixel format (a four-character code, see `PixelFormat`).
  final int pixelFormatType;

  /// Whether the width or height is dynamic.
  bool get hasDynamicSize => width < 0 || height < 0;

  @override
  String toString() =>
      'ImageDescriptor($name: ${width}x$height '
      '${_fourCC(pixelFormatType)})';
}

/// The signature of an inference function (Core AI's
/// `InferenceFunctionDescriptor`).
@immutable
final class FunctionDescriptor {
  /// Creates a descriptor. The maps preserve the function's argument order.
  FunctionDescriptor({
    required this.name,
    required Map<String, ValueDescriptor> inputs,
    required Map<String, ValueDescriptor> states,
    required Map<String, ValueDescriptor> outputs,
  }) : inputs = UnmodifiableMapView(inputs),
       states = UnmodifiableMapView(states),
       outputs = UnmodifiableMapView(outputs);

  /// Converts from the Pigeon representation.
  factory FunctionDescriptor.fromMessage(FunctionDescriptorMessage message) {
    Map<String, ValueDescriptor> byName(List<ValueDescriptorMessage> list) => {
      for (final item in list) item.name: ValueDescriptor.fromMessage(item),
    };
    return FunctionDescriptor(
      name: message.name,
      inputs: byName(message.inputs),
      states: byName(message.states),
      outputs: byName(message.outputs),
    );
  }

  /// The function name.
  final String name;

  /// Input descriptors, by name.
  final Map<String, ValueDescriptor> inputs;

  /// State descriptors, by name. Every state must be supplied to `run`.
  final Map<String, ValueDescriptor> states;

  /// Output descriptors, by name.
  final Map<String, ValueDescriptor> outputs;

  /// Whether the function has in-out state arguments.
  bool get isStateful => states.isNotEmpty;

  @override
  String toString() =>
      'FunctionDescriptor($name, inputs: '
      '${inputs.values.toList()}, states: ${states.values.toList()}, '
      'outputs: ${outputs.values.toList()})';
}

String _fourCC(int code) {
  final bytes = [24, 16, 8, 0].map((shift) => (code >> shift) & 0xFF);
  if (bytes.every((b) => b >= 0x20 && b < 0x7F)) {
    return "'${String.fromCharCodes(bytes)}'";
  }
  return '0x${code.toRadixString(16)}';
}

import 'package:flutter/foundation.dart';

import 'messages.g.dart';

/// Where Core ML may run a model (`MLComputeUnits`).
enum MLComputeUnits {
  /// The CPU only.
  cpuOnly,

  /// The CPU and the GPU.
  cpuAndGpu,

  /// Every available compute unit, including the Neural Engine. The default.
  all,

  /// The CPU and the Neural Engine, but not the GPU.
  cpuAndNeuralEngine;

  /// The Pigeon representation.
  ComputeUnitsMessage toMessage() => ComputeUnitsMessage.values[index];

  /// The public representation of [message].
  static MLComputeUnits fromMessage(ComputeUnitsMessage message) =>
      MLComputeUnits.values[message.index];
}

/// The element type of an [MLMultiArray] (`MLMultiArrayDataType`).
enum MLMultiArrayDataType {
  /// IEEE 754 half precision. Core ML's usual internal precision.
  float16(2),

  /// IEEE 754 single precision.
  float32(4),

  /// IEEE 754 double precision (`MLMultiArrayDataTypeDouble`).
  float64(8),

  /// 32-bit signed integer.
  int32(4),

  /// 8-bit signed integer. Needs iOS 26 / macOS 26.
  int8(1);

  const MLMultiArrayDataType(this.byteCount);

  /// The number of bytes one element occupies.
  final int byteCount;

  /// Whether this is a floating-point type.
  bool get isFloatingPoint =>
      this == float16 || this == float32 || this == float64;

  /// The Pigeon representation.
  MultiArrayDataTypeMessage toMessage() =>
      MultiArrayDataTypeMessage.values[index];

  /// The public representation of [message].
  static MLMultiArrayDataType fromMessage(MultiArrayDataTypeMessage message) =>
      MLMultiArrayDataType.values[message.index];
}

/// The type of a model feature (`MLFeatureType`).
enum MLFeatureType {
  /// Not a valid feature type.
  invalid,

  /// A 64-bit integer.
  int64,

  /// A double (`MLFeatureTypeDouble`).
  float64,

  /// A string.
  string,

  /// An image, carried by a `CVPixelBuffer`.
  image,

  /// An `MLMultiArray`.
  multiArray,

  /// A dictionary of numbers keyed by strings or int64s.
  dictionary,

  /// An `MLSequence` of strings or int64s.
  sequence,

  /// A state buffer of a stateful model.
  state;

  /// The Pigeon representation.
  FeatureTypeMessage toMessage() => FeatureTypeMessage.values[index];

  /// The public representation of [message].
  static MLFeatureType fromMessage(FeatureTypeMessage message) =>
      MLFeatureType.values[message.index];
}

/// How often a model's input shapes change
/// (`MLOptimizationHints.ReshapeFrequency`).
enum MLReshapeFrequency {
  /// Input shapes change on most predictions. The default.
  frequent,

  /// Input shapes are stable, so Core ML may re-optimize for each new shape.
  infrequent;

  /// The Pigeon representation.
  ReshapeFrequencyMessage toMessage() => ReshapeFrequencyMessage.values[index];
}

/// How aggressively Core ML specializes a model
/// (`MLOptimizationHints.SpecializationStrategy`).
enum MLSpecializationStrategy {
  /// Works well for most applications.
  defaults,

  /// Prefers prediction latency at the cost of load time, memory and disk.
  fastPrediction;

  /// The Pigeon representation.
  SpecializationStrategyMessage toMessage() =>
      SpecializationStrategyMessage.values[index];
}

/// How a multi-array's shape may vary (`MLMultiArrayShapeConstraintType`).
enum MLShapeConstraintType {
  /// Any shape is allowed.
  unspecified,

  /// One of [MLMultiArrayConstraint.enumeratedShapes].
  enumerated,

  /// Each dimension has its own range.
  range,
}

/// How an image's size may vary (`MLImageSizeConstraintType`).
enum MLImageSizeConstraintType {
  /// Any size is allowed.
  unspecified,

  /// One of [MLImageConstraint.enumeratedSizes].
  enumerated,

  /// Width and height each have a range.
  range,
}

/// A compute device Core ML can run on (`MLComputeDevice`).
@immutable
final class MLComputeDevice {
  /// Creates a device.
  const MLComputeDevice({
    required this.kind,
    required this.name,
    this.neuralEngineCoreCount,
    this.metalDeviceName,
  });

  /// Converts from the Pigeon representation.
  factory MLComputeDevice.fromMessage(ComputeDeviceMessage message) =>
      MLComputeDevice(
        kind: MLComputeDeviceKind.values[message.kind.index],
        name: message.name,
        neuralEngineCoreCount: message.neuralEngineCoreCount,
        metalDeviceName: message.metalDeviceName,
      );

  /// Which kind of device this is.
  final MLComputeDeviceKind kind;

  /// A readable name.
  final String name;

  /// The number of Neural Engine cores, for [MLComputeDeviceKind.neuralEngine].
  final int? neuralEngineCoreCount;

  /// The `MTLDevice` name, for [MLComputeDeviceKind.gpu].
  final String? metalDeviceName;

  @override
  bool operator ==(Object other) =>
      other is MLComputeDevice &&
      other.kind == kind &&
      other.name == name &&
      other.neuralEngineCoreCount == neuralEngineCoreCount &&
      other.metalDeviceName == metalDeviceName;

  @override
  int get hashCode =>
      Object.hash(kind, name, neuralEngineCoreCount, metalDeviceName);

  @override
  String toString() => switch (kind) {
    MLComputeDeviceKind.gpu => 'MLComputeDevice.gpu($metalDeviceName)',
    MLComputeDeviceKind.neuralEngine =>
      'MLComputeDevice.neuralEngine($neuralEngineCoreCount cores)',
    MLComputeDeviceKind.cpu => 'MLComputeDevice.cpu',
  };
}

/// The cases of `MLComputeDevice`.
enum MLComputeDeviceKind {
  /// `MLCPUComputeDevice`.
  cpu,

  /// `MLGPUComputeDevice`.
  gpu,

  /// `MLNeuralEngineComputeDevice`.
  neuralEngine,
}

/// Image encodings for [CoreML.encodeImage].
enum MLImageEncoding {
  /// Lossless PNG.
  png,

  /// Lossy JPEG.
  jpeg,
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'descriptors.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'native_resource.dart';
import 'scalar_type.dart';

part 'nd_array.dart';
part 'native_value.dart';
part 'pixel_buffer.dart';

/// A value passed to or returned from an [InferenceFunction]: an [NDArray],
/// a [PixelBuffer], or a [NativeValue] that stays on the native side.
///
/// Outputs can be matched exhaustively:
///
/// ```dart
/// switch (outputs['logits']) {
///   case NDArray array: print(array.toDoubleList());
///   case PixelBuffer image: print('${image.width}x${image.height}');
///   case NativeValue value: print('kept native: ${value.handle}');
///   case null: print('missing');
/// }
/// ```
sealed class InferenceValue {}

/// Converts an input value to its Pigeon message.
ValueMessage valueToMessage(InferenceValue value) => switch (value) {
  NDArray() => value.toMessage(),
  PixelBuffer() => value.toMessage(),
  NativeValue() => NativeValueRefMessage(handle: value.handle),
};

/// Converts an output message to a public value.
InferenceValue valueFromMessage(ValueMessage message) => switch (message) {
  NDArrayMessage() => NDArray.fromMessage(message),
  PixelBufferMessage() => PixelBuffer.fromMessage(message),
  NativeValueRefMessage() => adoptNativeValue(message.handle),
};

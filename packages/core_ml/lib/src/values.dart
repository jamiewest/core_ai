import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'messages.g.dart';
import 'types.dart';

part 'image.dart';
part 'multi_array.dart';

/// A value passed to, or returned from, an [MLModel] prediction
/// (`MLFeatureValue`).
///
/// Outputs can be matched exhaustively:
///
/// ```dart
/// switch (prediction['y']) {
///   case MLMultiArray array: print(array.toDoubleList());
///   case PixelBuffer image: print('${image.width}x${image.height}');
///   case MLStringValue value: print(value.value);
///   case null: print('missing');
///   default: break;
/// }
/// ```
sealed class MLFeatureValue {
  /// Allows subclasses to have const constructors.
  const MLFeatureValue();

  /// An int64 feature value.
  const factory MLFeatureValue.int64(int value) = MLInt64Value;

  /// A double feature value.
  const factory MLFeatureValue.float64(double value) = MLDoubleValue;

  /// A string feature value.
  const factory MLFeatureValue.string(String value) = MLStringValue;

  /// Converts to the Pigeon representation.
  FeatureValueMessage toMessage();
}

/// An `MLFeatureValue` holding an int64.
@immutable
final class MLInt64Value extends MLFeatureValue {
  /// Creates a value.
  const MLInt64Value(this.value);

  /// The integer.
  final int value;

  @override
  FeatureValueMessage toMessage() => Int64ValueMessage(value: value);

  @override
  bool operator ==(Object other) =>
      other is MLInt64Value && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MLInt64Value($value)';
}

/// An `MLFeatureValue` holding a double.
@immutable
final class MLDoubleValue extends MLFeatureValue {
  /// Creates a value.
  const MLDoubleValue(this.value);

  /// The number.
  final double value;

  @override
  FeatureValueMessage toMessage() => DoubleValueMessage(value: value);

  @override
  bool operator ==(Object other) =>
      other is MLDoubleValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MLDoubleValue($value)';
}

/// An `MLFeatureValue` holding a string.
@immutable
final class MLStringValue extends MLFeatureValue {
  /// Creates a value.
  const MLStringValue(this.value);

  /// The string.
  final String value;

  @override
  FeatureValueMessage toMessage() => StringValueMessage(value: value);

  @override
  bool operator ==(Object other) =>
      other is MLStringValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MLStringValue($value)';
}

/// An `MLFeatureValue` holding a dictionary of numbers, as classifiers
/// produce for their class probabilities.
///
/// Keys are either strings or int64s, never both.
@immutable
final class MLDictionaryValue extends MLFeatureValue {
  /// A dictionary keyed by strings.
  MLDictionaryValue.strings(Map<String, double> values)
    : stringKeyed = Map.unmodifiable(values),
      int64Keyed = null;

  /// A dictionary keyed by int64s.
  MLDictionaryValue.int64s(Map<int, double> values)
    : stringKeyed = null,
      int64Keyed = Map.unmodifiable(values);

  /// The string-keyed entries, or null when the keys are int64s.
  final Map<String, double>? stringKeyed;

  /// The int64-keyed entries, or null when the keys are strings.
  final Map<int, double>? int64Keyed;

  /// The entries with their keys as [Object]s (String or int).
  Map<Object, double> get values =>
      stringKeyed ?? int64Keyed?.map((k, v) => MapEntry(k, v)) ?? const {};

  @override
  FeatureValueMessage toMessage() =>
      DictionaryValueMessage(stringKeyed: stringKeyed, int64Keyed: int64Keyed);

  @override
  String toString() => 'MLDictionaryValue($values)';
}

/// An `MLSequence` of strings or int64s.
@immutable
final class MLSequenceValue extends MLFeatureValue {
  /// A sequence of strings.
  MLSequenceValue.strings(List<String> values)
    : strings = List.unmodifiable(values),
      int64s = null;

  /// A sequence of int64s.
  MLSequenceValue.int64s(List<int> values)
    : strings = null,
      int64s = List.unmodifiable(values);

  /// The strings, or null for an int64 sequence.
  final List<String>? strings;

  /// The integers, or null for a string sequence.
  final List<int>? int64s;

  @override
  FeatureValueMessage toMessage() =>
      SequenceValueMessage(strings: strings, int64s: int64s);

  @override
  String toString() => 'MLSequenceValue(${strings ?? int64s})';
}

/// An undefined `MLFeatureValue`, used to leave an optional input unset.
@immutable
final class MLUndefinedValue extends MLFeatureValue {
  /// Creates an undefined value of [featureType].
  const MLUndefinedValue(this.featureType);

  /// The type the value would have had.
  final MLFeatureType featureType;

  @override
  FeatureValueMessage toMessage() =>
      UndefinedValueMessage(featureType: featureType.toMessage());

  @override
  bool operator ==(Object other) =>
      other is MLUndefinedValue && other.featureType == featureType;

  @override
  int get hashCode => featureType.hashCode;

  @override
  String toString() => 'MLUndefinedValue(${featureType.name})';
}

/// Converts an output message to a public feature value.
MLFeatureValue featureValueFromMessage(FeatureValueMessage message) =>
    switch (message) {
      MultiArrayMessage() => MLMultiArray.fromMessage(message),
      PixelBufferMessage() => PixelBuffer.fromMessage(message),
      EncodedImageMessage() => EncodedImage(
        message.bytes ?? Uint8List(0),
        width: message.width,
        height: message.height,
        pixelFormatType: message.pixelFormatType,
      ),
      StringValueMessage() => MLStringValue(message.value),
      Int64ValueMessage() => MLInt64Value(message.value),
      DoubleValueMessage() => MLDoubleValue(message.value),
      DictionaryValueMessage() =>
        message.stringKeyed != null
            ? MLDictionaryValue.strings(message.stringKeyed!)
            : MLDictionaryValue.int64s(message.int64Keyed ?? const {}),
      SequenceValueMessage() =>
        message.strings != null
            ? MLSequenceValue.strings(message.strings!)
            : MLSequenceValue.int64s(message.int64s ?? const []),
      UndefinedValueMessage() => MLUndefinedValue(
        MLFeatureType.fromMessage(message.featureType),
      ),
    };

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Content the model generated against a schema (Apple's `GeneratedContent`).
///
/// [value] is the decoded JSON: a `Map`, `List`, `String`, `num`, `bool` or
/// null. While streaming, partial snapshots may be missing properties;
/// [isComplete] says whether generation finished.
@immutable
final class GeneratedContent {
  /// Wraps [json] text.
  factory GeneratedContent(String json, {bool isComplete = true}) {
    Object? value;
    try {
      value = jsonDecode(json);
    } on FormatException {
      value = null;
    }
    return GeneratedContent._(json, value, isComplete);
  }

  const GeneratedContent._(this.json, this.value, this.isComplete);

  /// The raw JSON text.
  final String json;

  /// The decoded value, or null if the partial JSON could not be decoded yet.
  final Object? value;

  /// Whether the model finished generating this content.
  final bool isComplete;

  /// The value as a JSON object.
  Map<String, Object?> get asMap => switch (value) {
    final Map<String, Object?> map => map,
    _ => throw StateError('The generated content is not an object: $json'),
  };

  /// The value as a JSON array.
  List<Object?> get asList => switch (value) {
    final List<Object?> list => list,
    _ => throw StateError('The generated content is not an array: $json'),
  };

  /// Property [name] of an object, or null when it is missing (which is
  /// common in partial snapshots).
  Object? operator [](String name) => switch (value) {
    final Map<String, Object?> map => map[name],
    _ => null,
  };

  @override
  String toString() =>
      'GeneratedContent(${isComplete ? 'complete' : 'partial'}, $json)';
}

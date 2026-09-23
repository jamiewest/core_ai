import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Builds the JSON Schema that Foundation Models uses for guided generation
/// (Apple's `DynamicGenerationSchema`).
///
/// ```dart
/// final schema = GenerationSchema(
///   DynamicGenerationSchema.object(
///     name: 'Recipe',
///     properties: [
///       SchemaProperty('title', DynamicGenerationSchema.string()),
///       SchemaProperty(
///         'servings',
///         DynamicGenerationSchema.integer(minimum: 1, maximum: 12),
///       ),
///       SchemaProperty(
///         'steps',
///         DynamicGenerationSchema.array(DynamicGenerationSchema.string()),
///       ),
///     ],
///   ),
/// );
/// ```
@immutable
final class DynamicGenerationSchema {
  const DynamicGenerationSchema._(
    this._fragment, {
    this.name,
    this.definitions = const {},
  });

  /// An object with named [properties].
  factory DynamicGenerationSchema.object({
    required String name,
    String? description,
    required List<SchemaProperty> properties,
  }) {
    final fragment = <String, Object?>{
      'type': 'object',
      'title': name,
      'description': ?description,
      'properties': {
        for (final property in properties)
          property.name: property.schema._referenceOrFragment(
            description: property.description,
          ),
      },
      'required': [
        for (final property in properties)
          if (!property.isOptional) property.name,
      ],
      'x-order': [for (final property in properties) property.name],
      'additionalProperties': false,
    };
    final definitions = <String, Map<String, Object?>>{};
    for (final property in properties) {
      definitions.addAll(property.schema._collectedDefinitions());
    }
    return DynamicGenerationSchema._(
      fragment,
      name: name,
      definitions: definitions,
    );
  }

  /// A value matching any one of [choices].
  factory DynamicGenerationSchema.anyOf({
    required String name,
    String? description,
    required List<DynamicGenerationSchema> choices,
  }) {
    if (choices.isEmpty) {
      throw ArgumentError.value(choices, 'choices', 'must not be empty');
    }
    final definitions = <String, Map<String, Object?>>{};
    for (final choice in choices) {
      definitions.addAll(choice._collectedDefinitions());
    }
    return DynamicGenerationSchema._(
      {
        'title': name,
        'description': ?description,
        'anyOf': [for (final choice in choices) choice._referenceOrFragment()],
      },
      name: name,
      definitions: definitions,
    );
  }

  /// A string limited to [values].
  factory DynamicGenerationSchema.enumeration(
    List<String> values, {
    String? description,
  }) => DynamicGenerationSchema._({
    'type': 'string',
    'description': ?description,
    'enum': values,
  });

  /// An array of [items].
  factory DynamicGenerationSchema.array(
    DynamicGenerationSchema items, {
    int? minimumElements,
    int? maximumElements,
  }) => DynamicGenerationSchema._({
    'type': 'array',
    'items': items._referenceOrFragment(),
    'minItems': ?minimumElements,
    'maxItems': ?maximumElements,
  }, definitions: items._collectedDefinitions());

  /// A string, optionally constrained.
  factory DynamicGenerationSchema.string({
    String? constant,
    List<String>? anyOf,
    String? pattern,
  }) => DynamicGenerationSchema._({
    'type': 'string',
    'const': ?constant,
    'enum': ?anyOf,
    'pattern': ?pattern,
  });

  /// An integer, optionally bounded.
  factory DynamicGenerationSchema.integer({int? minimum, int? maximum}) =>
      DynamicGenerationSchema._({
        'type': 'integer',
        'minimum': ?minimum,
        'maximum': ?maximum,
      });

  /// A floating-point number, optionally bounded.
  factory DynamicGenerationSchema.number({num? minimum, num? maximum}) =>
      DynamicGenerationSchema._({
        'type': 'number',
        'minimum': ?minimum,
        'maximum': ?maximum,
      });

  /// A Boolean.
  factory DynamicGenerationSchema.boolean() =>
      const DynamicGenerationSchema._({'type': 'boolean'});

  /// The null value.
  factory DynamicGenerationSchema.nullValue() =>
      const DynamicGenerationSchema._({'type': 'null'});

  /// A reference to another named schema, for recursive structures. Pass the
  /// referenced schema in `GenerationSchema`'s `dependencies`.
  factory DynamicGenerationSchema.reference(String name) =>
      DynamicGenerationSchema._({r'$ref': '#/\$defs/$name'});

  /// The name, for schemas that have one.
  final String? name;

  final Map<String, Object?> _fragment;
  final Map<String, Map<String, Object?>> definitions;

  bool get _isNamed => name != null && !_fragment.containsKey(r'$ref');

  /// Named schemas are referenced through `$defs`, like Apple's encoder.
  Map<String, Object?> _referenceOrFragment({String? description}) {
    if (_isNamed) return {r'$ref': '#/\$defs/$name'};
    if (description == null) return _fragment;
    return {..._fragment, 'description': description};
  }

  Map<String, Map<String, Object?>> _collectedDefinitions() => {
    ...definitions,
    if (_isNamed) name!: _fragment,
  };
}

/// One property of a [DynamicGenerationSchema.object].
@immutable
final class SchemaProperty {
  /// Creates a property.
  const SchemaProperty(
    this.name,
    this.schema, {
    this.description,
    this.isOptional = false,
  });

  /// The property name.
  final String name;

  /// The property's schema.
  final DynamicGenerationSchema schema;

  /// What the property means, which helps the model fill it in.
  final String? description;

  /// Whether the model may leave this property out.
  final bool isOptional;
}

/// A schema for guided generation (Apple's `GenerationSchema`).
@immutable
final class GenerationSchema {
  /// Builds a schema from [root], plus any [dependencies] referenced with
  /// [DynamicGenerationSchema.reference].
  factory GenerationSchema(
    DynamicGenerationSchema root, {
    List<DynamicGenerationSchema> dependencies = const [],
  }) {
    final definitions = <String, Map<String, Object?>>{
      ...root.definitions,
      for (final dependency in dependencies) ...{
        ...dependency.definitions,
        if (dependency.name != null) dependency.name!: dependency._fragment,
      },
    };
    final json = <String, Object?>{
      ...root._fragment,
      if (definitions.isNotEmpty) r'$defs': definitions,
    };
    return GenerationSchema._(json);
  }

  const GenerationSchema._(this.json);

  /// Wraps an existing JSON Schema.
  ///
  /// Missing `x-order`, `required` and `additionalProperties` keys are filled
  /// in, because Apple's decoder requires them.
  factory GenerationSchema.fromJsonSchema(Map<String, Object?> schema) =>
      GenerationSchema._(_normalize(schema) as Map<String, Object?>);

  /// The JSON Schema sent to Foundation Models.
  final Map<String, Object?> json;

  /// The schema's name (its `title`).
  String? get name => json['title'] as String?;

  /// The schema as JSON text.
  String toJsonString() => jsonEncode(json);

  static Object? _normalize(Object? node) {
    if (node is List) return [for (final item in node) _normalize(item)];
    if (node is! Map) return node;
    final map = node.cast<String, Object?>();
    final result = <String, Object?>{
      for (final entry in map.entries) entry.key: _normalize(entry.value),
    };
    if (map['type'] == 'object') {
      final properties = (map['properties'] as Map?)?.cast<String, Object?>();
      final keys = properties?.keys.toList() ?? const <String>[];
      result['properties'] = result['properties'] ?? <String, Object?>{};
      result['required'] = map['required'] ?? keys;
      result['x-order'] = map['x-order'] ?? keys;
      result['additionalProperties'] = map['additionalProperties'] ?? false;
    }
    return result;
  }

  @override
  String toString() => 'GenerationSchema(${name ?? 'unnamed'})';
}

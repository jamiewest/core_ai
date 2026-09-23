import 'dart:convert';

import 'content.dart';
import 'messages.g.dart';
import 'schema.dart';

/// What a [Tool] gives back to the model.
sealed class ToolOutput {
  const ToolOutput();

  /// Plain text.
  const factory ToolOutput.text(String text) = _TextOutput;

  /// Structured JSON built from [value] (a `Map`, `List` or primitive).
  const factory ToolOutput.json(Object? value) = _JsonOutput;

  /// The Pigeon representation.
  ToolResultMessage toMessage();
}

final class _TextOutput extends ToolOutput {
  const _TextOutput(this.text);

  final String text;

  @override
  ToolResultMessage toMessage() => ToolResultMessage(text: text);
}

final class _JsonOutput extends ToolOutput {
  const _JsonOutput(this.value);

  final Object? value;

  @override
  ToolResultMessage toMessage() =>
      ToolResultMessage(contentJson: jsonEncode(value));
}

/// A tool the model can call during a response (Apple's `Tool`).
///
/// The model decides when to call it, with arguments matching [parameters].
/// The call runs while the response is in flight, so a handler must not start
/// another request on the same session.
abstract base class Tool {
  /// Creates a tool.
  const Tool();

  /// The name the model uses. Keep it short and descriptive.
  String get name;

  /// What the tool does, and when to use it.
  String get description;

  /// The schema of the tool's arguments.
  GenerationSchema get parameters;

  /// Whether the schema is included in the session's instructions.
  bool get includesSchemaInInstructions => true;

  /// Runs the tool.
  Future<ToolOutput> call(GeneratedContent arguments);

  /// The Pigeon representation.
  ToolDefinitionMessage toMessage() => ToolDefinitionMessage(
    name: name,
    toolDescription: description,
    parametersJson: parameters.toJsonString(),
    includesSchemaInInstructions: includesSchemaInInstructions,
  );
}

/// A [Tool] backed by a function.
///
/// ```dart
/// FunctionTool(
///   name: 'get_weather',
///   description: 'Gets the current weather for a city.',
///   parameters: GenerationSchema(
///     DynamicGenerationSchema.object(
///       name: 'WeatherArguments',
///       properties: [
///         SchemaProperty('city', DynamicGenerationSchema.string()),
///       ],
///     ),
///   ),
///   handler: (arguments) async =>
///       ToolOutput.text(await weatherFor(arguments['city']! as String)),
/// )
/// ```
final class FunctionTool extends Tool {
  /// Creates a tool that runs [handler].
  const FunctionTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
    this.includesSchemaInInstructions = true,
  });

  @override
  final String name;

  @override
  final String description;

  @override
  final GenerationSchema parameters;

  @override
  final bool includesSchemaInInstructions;

  /// Runs the tool.
  final Future<ToolOutput> Function(GeneratedContent arguments) handler;

  @override
  Future<ToolOutput> call(GeneratedContent arguments) => handler(arguments);
}

/// Tools that Apple implements, available from iOS 27 / macOS 27.
enum BuiltInTool {
  /// Vision's `OCRTool`: reads text from an image attached to the prompt.
  ocr,

  /// Vision's `BarcodeReaderTool`: reads barcodes and QR codes from an
  /// attached image.
  barcodeReader;

  /// The Pigeon representation.
  BuiltInToolMessage toMessage() => BuiltInToolMessage.values[index];
}

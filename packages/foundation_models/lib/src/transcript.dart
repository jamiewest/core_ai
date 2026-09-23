import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'content.dart';
import 'messages.g.dart';
import 'schema.dart';

/// One piece of an entry's content (Apple's `Transcript.Segment`).
@immutable
sealed class TranscriptSegment {
  const TranscriptSegment(this.id);

  /// Converts from the Pigeon representation.
  factory TranscriptSegment.fromMessage(SegmentMessage message) =>
      switch (message.kind) {
        SegmentKindMessage.text => TextSegment(message.id, message.text ?? ''),
        SegmentKindMessage.structure => StructuredSegment(
          message.id,
          GeneratedContent(message.contentJson ?? '{}'),
          schemaName: message.schemaName ?? '',
        ),
        SegmentKindMessage.attachment => AttachmentSegment(
          message.id,
          label: message.attachmentLabel,
        ),
      };

  /// The segment's identifier.
  final String id;
}

/// Plain text.
final class TextSegment extends TranscriptSegment {
  /// Creates a text segment.
  const TextSegment(super.id, this.text);

  /// The text.
  final String text;

  @override
  String toString() => text;
}

/// Content generated against a schema.
final class StructuredSegment extends TranscriptSegment {
  /// Creates a structured segment.
  const StructuredSegment(super.id, this.content, {required this.schemaName});

  /// The generated content.
  final GeneratedContent content;

  /// The name of the schema it matches.
  final String schemaName;

  @override
  String toString() => '$schemaName ${content.json}';
}

/// An attached image.
final class AttachmentSegment extends TranscriptSegment {
  /// Creates an attachment segment.
  const AttachmentSegment(super.id, {this.label});

  /// The attachment's label, if it has one.
  final String? label;

  @override
  String toString() => 'attachment(${label ?? id})';
}

/// A tool call the model made.
@immutable
final class TranscriptToolCall {
  /// Creates a tool call.
  const TranscriptToolCall({
    required this.id,
    required this.toolName,
    required this.arguments,
  });

  /// Converts from the Pigeon representation.
  factory TranscriptToolCall.fromMessage(ToolCallMessage message) =>
      TranscriptToolCall(
        id: message.id,
        toolName: message.toolName,
        arguments: GeneratedContent(message.argumentsJson),
      );

  /// The call's identifier.
  final String id;

  /// The tool that was called.
  final String toolName;

  /// The arguments the model produced.
  final GeneratedContent arguments;
}

/// A tool as the model sees it.
@immutable
final class TranscriptToolDefinition {
  /// Creates a definition.
  const TranscriptToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Converts from the Pigeon representation.
  factory TranscriptToolDefinition.fromMessage(ToolDefinitionMessage message) {
    var schema = const <String, Object?>{};
    try {
      schema = (jsonDecode(message.parametersJson) as Map)
          .cast<String, Object?>();
    } on FormatException {
      schema = const {};
    }
    return TranscriptToolDefinition(
      name: message.name,
      description: message.toolDescription,
      parameters: GenerationSchema.fromJsonSchema(schema),
    );
  }

  /// The tool name.
  final String name;

  /// What the tool does.
  final String description;

  /// The schema of its arguments.
  final GenerationSchema parameters;
}

/// One entry of a [Transcript] (Apple's `Transcript.Entry`).
@immutable
sealed class TranscriptEntry {
  const TranscriptEntry({required this.id, required this.segments});

  /// Converts from the Pigeon representation.
  factory TranscriptEntry.fromMessage(TranscriptEntryMessage message) {
    final segments = [
      for (final segment in message.segments)
        TranscriptSegment.fromMessage(segment),
    ];
    return switch (message.kind) {
      TranscriptEntryKindMessage.instructions => InstructionsEntry(
        id: message.id,
        segments: segments,
        tools: [
          for (final tool in message.toolDefinitions)
            TranscriptToolDefinition.fromMessage(tool),
        ],
      ),
      TranscriptEntryKindMessage.prompt => PromptEntry(
        id: message.id,
        segments: segments,
        responseFormatName: message.responseFormatName,
      ),
      TranscriptEntryKindMessage.toolCalls => ToolCallsEntry(
        id: message.id,
        segments: segments,
        calls: [
          for (final call in message.toolCalls)
            TranscriptToolCall.fromMessage(call),
        ],
      ),
      TranscriptEntryKindMessage.toolOutput => ToolOutputEntry(
        id: message.id,
        segments: segments,
        toolName: message.toolName ?? '',
      ),
      TranscriptEntryKindMessage.response => ResponseEntry(
        id: message.id,
        segments: segments,
      ),
      TranscriptEntryKindMessage.reasoning => ReasoningEntry(
        id: message.id,
        segments: segments,
      ),
    };
  }

  /// The entry's identifier.
  final String id;

  /// The entry's content.
  final List<TranscriptSegment> segments;

  /// All text in this entry, joined.
  String get text =>
      segments.whereType<TextSegment>().map((s) => s.text).join();
}

/// The session's instructions and tools.
final class InstructionsEntry extends TranscriptEntry {
  /// Creates an instructions entry.
  const InstructionsEntry({
    required super.id,
    required super.segments,
    required this.tools,
  });

  /// The tools available to the session.
  final List<TranscriptToolDefinition> tools;
}

/// A prompt from the app.
final class PromptEntry extends TranscriptEntry {
  /// Creates a prompt entry.
  const PromptEntry({
    required super.id,
    required super.segments,
    this.responseFormatName,
  });

  /// The name of the schema the response must match, if any.
  final String? responseFormatName;
}

/// Tool calls the model made.
final class ToolCallsEntry extends TranscriptEntry {
  /// Creates a tool-calls entry.
  const ToolCallsEntry({
    required super.id,
    required super.segments,
    required this.calls,
  });

  /// The calls.
  final List<TranscriptToolCall> calls;
}

/// The output a tool returned.
final class ToolOutputEntry extends TranscriptEntry {
  /// Creates a tool-output entry.
  const ToolOutputEntry({
    required super.id,
    required super.segments,
    required this.toolName,
  });

  /// The tool that produced it.
  final String toolName;
}

/// A response from the model.
final class ResponseEntry extends TranscriptEntry {
  /// Creates a response entry.
  const ResponseEntry({required super.id, required super.segments});
}

/// The model's reasoning, when the model supports it.
final class ReasoningEntry extends TranscriptEntry {
  /// Creates a reasoning entry.
  const ReasoningEntry({required super.id, required super.segments});
}

/// Everything a session has seen and produced (Apple's `Transcript`).
///
/// Persist [json] to resume a conversation later with
/// `LanguageModelSession.create(transcript: ...)`.
@immutable
final class Transcript {
  /// Creates a transcript.
  const Transcript({required this.entries, required this.json});

  /// Restores a transcript from previously persisted [json].
  ///
  /// [entries] is empty until the platform decodes it; use
  /// `FoundationModels.decodeTranscript` for a parsed copy.
  const Transcript.fromJson(String json) : this(entries: const [], json: json);

  /// Converts from the Pigeon representation.
  factory Transcript.fromMessage(TranscriptMessage message) => Transcript(
    entries: [
      for (final entry in message.entries) TranscriptEntry.fromMessage(entry),
    ],
    json: message.json,
  );

  /// The entries, oldest first.
  final List<TranscriptEntry> entries;

  /// The transcript as JSON, for persistence.
  final String json;

  @override
  String toString() => 'Transcript(${entries.length} entries)';
}

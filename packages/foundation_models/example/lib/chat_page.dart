import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:foundation_models/foundation_models.dart';

/// A chat against Apple's language models, showing streaming, a tool the
/// model can call, and guided generation.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _messages = <_Message>[];
  final _clock = _ClockTool();

  LanguageModelSession? _session;
  StreamSubscription<ResponseSnapshot<String>>? _subscription;
  ModelAvailability? _availability;
  LanguageModelInfo? _info;
  bool _useCloud = false;
  bool _busy = false;

  LanguageModel get _model => _useCloud
      ? const PrivateCloudComputeLanguageModel()
      : SystemLanguageModel.defaultModel;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() {
      _availability = null;
      _info = null;
      _messages.clear();
    });
    await _subscription?.cancel();
    await _session?.dispose();
    _session = null;
    final availability = await _model.availability();
    if (!mounted) return;
    setState(() => _availability = availability);
    if (!availability.isAvailable) return;
    try {
      final info = await _model.info();
      final session = await LanguageModelSession.create(
        model: _model,
        instructions:
            'You are a helpful assistant inside a Flutter sample app. '
            'Answer in at most three sentences. Use the clock tool whenever '
            'the user asks about the current time.',
        tools: [_clock],
      );
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() {
        _info = info;
        _session = session;
      });
    } on FoundationModelsException catch (error, stack) {
      developer.log(
        'Could not start a session',
        error: error,
        stackTrace: stack,
      );
      if (mounted) setState(() => _messages.add(_Message.error('$error')));
    }
  }

  Future<void> _send() async {
    final session = _session;
    final text = _input.text.trim();
    if (session == null || text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _busy = true;
      _messages
        ..add(_Message.user(text))
        ..add(_Message.model(''));
    });
    _subscription = session
        .streamResponse(text)
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() => _messages.last = _Message.model(snapshot.content));
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _messages.last = _Message.error('$error');
              _busy = false;
            });
          },
          onDone: () {
            if (mounted) setState(() => _busy = false);
          },
        );
  }

  Future<void> _summarize() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    final schema = GenerationSchema(
      DynamicGenerationSchema.object(
        name: 'Summary',
        description: 'A summary of this conversation.',
        properties: [
          SchemaProperty('topic', DynamicGenerationSchema.string()),
          SchemaProperty(
            'sentiment',
            DynamicGenerationSchema.string(
              anyOf: ['positive', 'neutral', 'negative'],
            ),
          ),
          SchemaProperty(
            'keyPoints',
            DynamicGenerationSchema.array(
              DynamicGenerationSchema.string(),
              minimumElements: 1,
              maximumElements: 3,
            ),
          ),
        ],
      ),
    );
    try {
      final response = await session.respondWithSchema(
        'Summarize our conversation so far.',
        schema,
      );
      if (!mounted) return;
      setState(() => _messages.add(_Message.structured(response.content.json)));
    } on FoundationModelsException catch (error) {
      if (mounted) setState(() => _messages.add(_Message.error('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _session?.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foundation Models'),
        actions: [
          Row(
            children: [
              const Text('Cloud'),
              Switch(
                value: _useCloud,
                onChanged: (value) {
                  setState(() => _useCloud = value);
                  unawaited(_start());
                },
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_info != null)
            _InfoBar(info: _info!, isCloud: _useCloud, tool: _clock),
          if (availability != null && !availability.isAvailable)
            Expanded(child: _Unavailable(availability: availability))
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) =>
                    _Bubble(message: _messages[index]),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: _session != null && !_busy,
                    decoration: const InputDecoration(
                      hintText: 'Ask something, or ask for the time',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton.filled(
                  onPressed: _session == null || _busy ? null : _send,
                  icon: const Icon(Icons.send),
                  tooltip: 'Send',
                ),
                IconButton.outlined(
                  onPressed: _session == null || _busy ? null : _summarize,
                  icon: const Icon(Icons.summarize),
                  tooltip: 'Summarize as JSON',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({
    required this.info,
    required this.isCloud,
    required this.tool,
  });

  final LanguageModelInfo info;
  final bool isCloud;
  final _ClockTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${isCloud ? 'Private Cloud Compute' : 'On device'} · '
        '${info.variantName ?? 'model'} · context ${info.contextSize} tokens · '
        'tool calls: ${tool.callCount}',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.availability});

  final ModelAvailability availability;

  @override
  Widget build(BuildContext context) {
    final message = switch (availability.reason) {
      ModelUnavailableReason.appleIntelligenceNotEnabled =>
        'Turn on Apple Intelligence in System Settings.',
      ModelUnavailableReason.deviceNotEligible =>
        'This device does not support Apple Intelligence.',
      ModelUnavailableReason.modelNotReady =>
        'The model is still downloading. Try again shortly.',
      ModelUnavailableReason.systemNotReady =>
        'Private Cloud Compute is not ready on this device.',
      ModelUnavailableReason.frameworkUnavailable =>
        'Foundation Models needs iOS 26 or macOS 26 or later.',
      _ => 'The model is unavailable.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, alignment) = switch (message.kind) {
      _Kind.user => (scheme.primary, scheme.onPrimary, Alignment.centerRight),
      _Kind.model => (
        scheme.surfaceContainerHigh,
        scheme.onSurface,
        Alignment.centerLeft,
      ),
      _Kind.structured => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Alignment.centerLeft,
      ),
      _Kind.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Alignment.centerLeft,
      ),
    };
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          message.text.isEmpty ? '…' : message.text,
          style: TextStyle(
            color: foreground,
            fontFamily: message.kind == _Kind.structured ? 'Menlo' : null,
          ),
        ),
      ),
    );
  }
}

enum _Kind { user, model, structured, error }

class _Message {
  const _Message(this.kind, this.text);

  const _Message.user(String text) : this(_Kind.user, text);
  const _Message.model(String text) : this(_Kind.model, text);
  const _Message.structured(String text) : this(_Kind.structured, text);
  const _Message.error(String text) : this(_Kind.error, text);

  final _Kind kind;
  final String text;
}

/// A tool the model can call to find out what time it is.
final class _ClockTool extends Tool {
  int callCount = 0;

  @override
  String get name => 'get_current_time';

  @override
  String get description =>
      'Returns the current local time. Use it whenever the user asks what '
      'time or date it is.';

  @override
  GenerationSchema get parameters => GenerationSchema(
    DynamicGenerationSchema.object(
      name: 'ClockArguments',
      properties: [
        SchemaProperty(
          'timeZone',
          DynamicGenerationSchema.string(),
          description: 'Ignored; the device clock is used.',
          isOptional: true,
        ),
      ],
    ),
  );

  @override
  Future<ToolOutput> call(GeneratedContent arguments) async {
    callCount++;
    return ToolOutput.json({'now': DateTime.now().toIso8601String()});
  }
}

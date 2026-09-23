import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:image_playground/image_playground.dart';

void main() => runApp(const ImagePlaygroundExampleApp());

/// Opens Apple's Image Playground sheet from Flutter.
class ImagePlaygroundExampleApp extends StatelessWidget {
  /// Creates the app.
  const ImagePlaygroundExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepOrange,
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: 'Image Playground',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const PlaygroundPage(),
    );
  }
}

/// A prompt, a style and the image the user created.
class PlaygroundPage extends StatefulWidget {
  /// Creates the page.
  const PlaygroundPage({super.key});

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  final _prompt = TextEditingController(text: 'A lighthouse at sunset');
  ImagePlaygroundCapabilities? _capabilities;
  ImagePlaygroundStyle? _style;
  ImagePlaygroundSession? _session;
  ImagePlaygroundResult? _result;
  String _status = 'Checking availability…';

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _session?.dispose();
    super.dispose();
  }

  Future<void> _loadCapabilities() async {
    final capabilities = await ImagePlayground.capabilities();
    if (!mounted) return;
    setState(() {
      _capabilities = capabilities;
      _status = !capabilities.isSupported
          ? 'Image Playground needs iOS 18.1 or macOS 15.1.'
          : capabilities.isAvailable
          ? 'Ready.'
          : 'Image Playground is unavailable. Check Apple Intelligence.';
    });
  }

  Future<void> _create() async {
    final prompt = _prompt.text.trim();
    final style = _style;
    setState(() => _status = 'Waiting for Image Playground…');
    try {
      final session = _session = await ImagePlayground.prepare(
        concepts: [if (prompt.isNotEmpty) ImagePlaygroundConcept.text(prompt)],
        allowedStyles: style == null ? null : [style],
        selectedStyle: style,
      );
      if (mounted) setState(() {});
      final result = await session.present();
      if (!mounted) return;
      setState(() {
        _result = result ?? _result;
        _status = result == null
            ? 'Cancelled.'
            : 'Created a ${result.width}×${result.height} image.';
      });
    } on ImagePlaygroundException catch (error, stack) {
      log('Image Playground failed', error: error, stackTrace: stack);
      if (mounted) setState(() => _status = error.message);
    } finally {
      final session = _session;
      _session = null;
      await session?.dispose();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    final ready = capabilities?.isAvailable ?? false;
    final open = _session != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Image Playground')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _prompt,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Describe an image',
              hintText: 'Leave empty to start from scratch',
              border: OutlineInputBorder(),
            ),
          ),
          if (capabilities != null && capabilities.styles.isNotEmpty) ...[
            const SizedBox(height: 12),
            _StylePicker(
              styles: capabilities.styles,
              selected: _style,
              onChanged: open
                  ? null
                  : (style) => setState(() => _style = style),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: ready && !open ? _create : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Open Image Playground'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: open ? () => _session?.cancel() : null,
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          if (_result case final result?) _ResultView(result),
        ],
      ),
    );
  }
}

class _StylePicker extends StatelessWidget {
  const _StylePicker({
    required this.styles,
    required this.selected,
    required this.onChanged,
  });

  final List<ImagePlaygroundStyle> styles;
  final ImagePlaygroundStyle? selected;
  final ValueChanged<ImagePlaygroundStyle?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Default'),
          selected: selected == null,
          onSelected: onChanged == null ? null : (_) => onChanged(null),
        ),
        for (final style in styles)
          ChoiceChip(
            label: Text(style.name),
            selected: selected == style,
            onSelected: onChanged == null ? null : (_) => onChanged(style),
          ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView(this.result);

  final ImagePlaygroundResult result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              result.bytes,
              semanticLabel: result.contentDescription ?? 'Created image',
              errorBuilder: (context, error, stack) =>
                  Text('Flutter cannot display ${result.typeIdentifier} data.'),
            ),
          ),
          if (result.contentDescription case final description?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(description),
            ),
        ],
      ),
    );
  }
}

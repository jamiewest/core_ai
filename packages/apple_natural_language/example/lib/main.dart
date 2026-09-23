import 'dart:developer';

import 'package:apple_natural_language/apple_natural_language.dart';
import 'package:flutter/material.dart';

import 'analysis.dart';

void main() => runApp(const NaturalLanguageExampleApp());

/// Analyzes text with Apple's Natural Language framework.
class NaturalLanguageExampleApp extends StatelessWidget {
  /// Creates the app.
  const NaturalLanguageExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    ColorScheme scheme(Brightness brightness) =>
        ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);
    return MaterialApp(
      title: 'Natural Language',
      theme: ThemeData(colorScheme: scheme(Brightness.light)),
      darkTheme: ThemeData(colorScheme: scheme(Brightness.dark)),
      home: const AnalyzerPage(),
    );
  }
}

/// A text box and what the framework finds in it.
class AnalyzerPage extends StatefulWidget {
  /// Creates the page.
  const AnalyzerPage({super.key});

  @override
  State<AnalyzerPage> createState() => _AnalyzerPageState();
}

class _AnalyzerPageState extends State<AnalyzerPage> {
  final _text = TextEditingController(
    text:
        'Tim Cook flew to Paris to meet engineers from Apple. '
        'They were thrilled with the wonderful new products!',
  );
  final _word = TextEditingController(text: 'coffee');
  TextAnalysis? _analysis;
  List<Neighbor>? _similar;
  Embedding? _embedding;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _text.dispose();
    _word.dispose();
    _embedding?.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on NaturalLanguageException catch (error, stack) {
      log('Analysis failed', error: error, stackTrace: stack);
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() => _run(() async {
    final analysis = await TextAnalysis.of(_text.text);
    setState(() => _analysis = analysis);
  });

  Future<void> _findSimilar() => _run(() async {
    final embedding = _embedding ??= await Embedding.wordEmbedding('en');
    final similar = await embedding.neighbors(
      _word.text.trim().toLowerCase(),
      maximumCount: 8,
    );
    setState(() => _similar = similar);
  });

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return Scaffold(
      appBar: AppBar(title: const Text('Natural Language')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _analyze,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Analyze'),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (analysis != null) _AnalysisView(analysis),
          const Divider(height: 32),
          _SimilarWords(
            controller: _word,
            busy: _busy,
            onSearch: _findSimilar,
            results: _similar,
          ),
        ],
      ),
    );
  }
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView(this.analysis);

  final TextAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final sentiment = analysis.sentiment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Language',
          icon: Icons.translate,
          children: [
            for (final language in analysis.languages)
              Chip(label: Text('$language')),
          ],
        ),
        _Section(
          title: 'Sentiment',
          icon: Icons.mood,
          children: [
            Chip(
              label: Text(
                sentiment == null
                    ? 'Unscored'
                    : '${sentiment.toStringAsFixed(2)} '
                          '${sentiment >= 0 ? 'positive' : 'negative'}',
              ),
            ),
          ],
        ),
        _Section(
          title: 'Named entities',
          icon: Icons.person_pin_circle,
          children: [
            for (final entity in analysis.entities)
              Chip(label: Text('${entity.text} · ${entity.tag}')),
          ],
        ),
        _Section(
          title: 'Parts of speech',
          icon: Icons.segment,
          children: [
            for (final word in analysis.partsOfSpeech)
              Tooltip(
                message: word.tag ?? 'Unknown',
                child: Chip(
                  label: Text(word.text),
                  avatar: CircleAvatar(
                    child: Text(word.tag?.substring(0, 1) ?? '?'),
                  ),
                ),
              ),
          ],
        ),
        _Section(
          title: 'Lemmas',
          icon: Icons.menu_book,
          children: [
            for (final (word, lemma) in analysis.lemmas)
              Chip(label: Text('$word → $lemma')),
          ],
        ),
      ],
    );
  }
}

class _SimilarWords extends StatelessWidget {
  const _SimilarWords({
    required this.controller,
    required this.busy,
    required this.onSearch,
    required this.results,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSearch;
  final List<Neighbor>? results;

  @override
  Widget build(BuildContext context) {
    final results = this.results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Word',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onSearch(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: busy ? null : onSearch,
              child: const Text('Similar words'),
            ),
          ],
        ),
        if (results != null)
          _Section(
            title: 'Nearest in the word embedding',
            icon: Icons.hub,
            children: [
              for (final neighbor in results) Chip(label: Text('$neighbor')),
            ],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (children.isEmpty)
            const Text('None found')
          else
            Wrap(spacing: 6, runSpacing: 6, children: children),
        ],
      ),
    );
  }
}

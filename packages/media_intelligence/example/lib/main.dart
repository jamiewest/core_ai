import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:media_intelligence/media_intelligence.dart';

import 'fixtures.dart';

void main() => runApp(const MediaIntelligenceExampleApp());

/// Demonstrates video highlights and face grouping on bundled media.
class MediaIntelligenceExampleApp extends StatelessWidget {
  /// Creates the app.
  const MediaIntelligenceExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: 'Media Intelligence',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const MediaPage(),
    );
  }
}

/// Runs each analysis on the sample media.
class MediaPage extends StatefulWidget {
  /// Creates the page.
  const MediaPage({super.key});

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  MediaFixtures? _fixtures;
  bool? _supported;
  bool _busy = false;
  String? _error;
  VideoAnalysis? _video;
  List<AssetFaces>? _faces;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fixtures?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final supported = await MediaIntelligence.isSupported();
    final fixtures = supported ? await MediaFixtures.load() : null;
    if (!mounted) {
      await fixtures?.dispose();
      return;
    }
    setState(() {
      _supported = supported;
      _fixtures = fixtures;
    });
  }

  Future<void> _run(Future<void> Function(MediaFixtures fixtures) body) async {
    final fixtures = _fixtures;
    if (fixtures == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body(fixtures);
    } on MediaIntelligenceException catch (error, stack) {
      log('Analysis failed', error: error, stackTrace: stack);
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyzeVideo() => _run((fixtures) async {
    final video = await VideoAnalyzer.analyze(fixtures.clip);
    if (mounted) setState(() => _video = video);
  });

  Future<void> _scanFaces() => _run((fixtures) async {
    final analyzer = await FaceGroupAnalyzer.open(fixtures.libraryDirectory);
    try {
      final faces = await analyzer.insertOrUpdate([fixtures.scene]).toList();
      await analyzer.update();
      if (mounted) setState(() => _faces = faces);
    } finally {
      await analyzer.dispose();
    }
  });

  @override
  Widget build(BuildContext context) {
    final supported = _supported;
    return Scaffold(
      appBar: AppBar(title: const Text('Media Intelligence')),
      body: supported == null
          ? const Center(child: CircularProgressIndicator())
          : !supported
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('MediaIntelligence needs iOS 27 or macOS 27.'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _VideoCard(
                  busy: _busy,
                  analysis: _video,
                  onAnalyze: _analyzeVideo,
                ),
                const SizedBox(height: 12),
                _FacesCard(busy: _busy, results: _faces, onScan: _scanFaces),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.busy,
    required this.analysis,
    required this.onAnalyze,
  });

  final bool busy;
  final VideoAnalysis? analysis;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final analysis = this.analysis;
    final highlights = analysis?.highlights;
    final keyFrame = analysis?.keyFrame;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Video', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'A 6-second clip that cuts to a new scene at 3 seconds.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onAnalyze,
              icon: const Icon(Icons.movie_filter),
              label: const Text('Find highlights'),
            ),
            if (highlights != null) ...[
              const SizedBox(height: 12),
              _Timeline(highlights: highlights, keyFrame: keyFrame),
              const SizedBox(height: 8),
              for (final range in highlights.highlights)
                Text(
                  'Highlight: ${_seconds(range.start)}–${_seconds(range.end)}',
                ),
            ],
            if (keyFrame != null) Text('Key frame: ${_seconds(keyFrame)}'),
            if (analysis?.highlightsError case final error?)
              Text('Highlights failed: ${error.message}'),
            if (analysis?.keyFrameError case final error?)
              Text('Key frame failed: ${error.message}'),
          ],
        ),
      ),
    );
  }

  static String _seconds(Duration value) =>
      '${(value.inMilliseconds / 1000).toStringAsFixed(1)} s';
}

/// Draws highlight levels across the clip, with the key frame marked.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.highlights, required this.keyFrame});

  final HighlightAnalysis highlights;
  final Duration? keyFrame;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final levels = highlights.levels;
    final total = levels.isEmpty ? Duration.zero : levels.last.range.end;
    return Semantics(
      key: const Key('highlight-timeline'),
      label: 'Highlight timeline',
      child: SizedBox(
        height: 32,
        child: LayoutBuilder(
          builder: (context, constraints) {
            double x(Duration time) => total == Duration.zero
                ? 0
                : constraints.maxWidth *
                      time.inMicroseconds /
                      total.inMicroseconds;
            final keyFrame = this.keyFrame;
            return Stack(
              children: [
                for (final level in levels)
                  Positioned(
                    left: x(level.range.start),
                    width: x(level.range.duration),
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Color.lerp(
                        colors.surfaceContainerHighest,
                        colors.primary,
                        level.level.clamp(0, 1),
                      )!,
                    ),
                  ),
                if (keyFrame != null)
                  Positioned(
                    left: x(keyFrame) - 1,
                    width: 3,
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(color: colors.tertiary),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FacesCard extends StatelessWidget {
  const _FacesCard({
    required this.busy,
    required this.results,
    required this.onScan,
  });

  final bool busy;
  final List<AssetFaces>? results;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final results = this.results;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Faces', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'Adds a sample image to a face library. Use your own photos of '
              'people to see faces grouped into people.',
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: busy ? null : onScan,
              icon: const Icon(Icons.face),
              label: const Text('Scan sample image'),
            ),
            if (results != null)
              for (final asset in results)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${asset.assetId}: ${asset.faces.length} '
                    '${asset.faces.length == 1 ? 'face' : 'faces'}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:apple_sound_analysis/apple_sound_analysis.dart';
import 'package:flutter/material.dart';

import 'fixtures.dart';

void main() => runApp(const SoundAnalysisExampleApp());

/// Demonstrates file, PCM and microphone sound classification.
class SoundAnalysisExampleApp extends StatelessWidget {
  /// Creates the demo.
  const SoundAnalysisExampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sound Analysis',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
    ),
    home: const _SoundPage(),
  );
}

class _SoundPage extends StatefulWidget {
  const _SoundPage();
  @override
  State<_SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<_SoundPage> {
  SoundFixtures? _fixtures;
  StreamSubscription<ClassificationResult>? _subscription;
  SoundStreamClassifier? _pcm;
  final _results = <ClassificationResult>[];
  bool _loading = true, _supported = false, _running = false, _custom = false;
  bool _disposed = false;
  int _generation = 0;
  String? _error;
  String _status = 'Choose an audio source.';
  bool get _alive => mounted && !_disposed;
  SoundClassifier get _classifier => _custom
      ? SoundClassifier.model(_fixtures!.model)
      : const SoundClassifier.builtIn();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final supported = await SoundAnalyzer.isSupported();
      final fixtures = supported ? await SoundFixtures.load() : null;
      if (!_alive) {
        await fixtures?.dispose();
        return;
      }
      setState(() {
        _supported = supported;
        _fixtures = fixtures;
        _loading = false;
      });
    } on Object catch (error, stack) {
      _fail(error, stack);
      if (_alive) setState(() => _loading = false);
    }
  }

  void _fail(Object error, StackTrace stack) {
    log('Sound analysis failed', error: error, stackTrace: stack);
    if (_alive) {
      setState(() {
        _error = error is SoundAnalysisException ? error.message : '$error';
        _running = false;
      });
    }
  }

  int _begin(String status) {
    final generation = ++_generation;
    setState(() {
      _running = true;
      _error = null;
      _results.clear();
      _status = status;
    });
    return generation;
  }

  bool _current(int generation) => _alive && generation == _generation;

  void _listen(Stream<ClassificationResult> results, int generation) {
    _subscription = results.listen(
      (result) {
        if (!_current(generation)) return;
        setState(() {
          _results.add(result);
          if (_results.length > 40) _results.removeAt(0);
        });
      },
      onError: (Object error, StackTrace stack) {
        if (_current(generation)) _fail(error, stack);
      },
      onDone: () {
        if (_current(generation)) {
          setState(() {
            _running = false;
            _status = 'Analysis complete.';
            _subscription = null;
          });
        }
      },
    );
  }

  void _file(bool tone) {
    final generation = _begin(
      tone ? 'Analyzing the tone…' : 'Analyzing speech…',
    );
    _listen(
      SoundAnalyzer.classifyFile(
        tone ? _fixtures!.tone : _fixtures!.speech,
        classifier: _classifier,
        maximumClassifications: 3,
      ),
      generation,
    );
  }

  Future<void> _streamPcm() async {
    final generation = _begin('Feeding tone samples…');
    SoundStreamClassifier? stream;
    try {
      final samples = decodeFixtureWav(
        await File(_fixtures!.tone).readAsBytes(),
      );
      if (!_current(generation)) return;
      stream = await SoundStreamClassifier.create(
        sampleRate: 16000,
        classifier: _classifier,
        maximumClassifications: 3,
      );
      if (!_current(generation)) {
        await stream.cancel();
        return;
      }
      _pcm = stream;
      _listen(stream.results, generation);
      for (var start = 0; start < samples.length; start += 4096) {
        if (!_current(generation)) return;
        await stream.add(
          Float32List.sublistView(
            samples,
            start,
            (start + 4096).clamp(0, samples.length),
          ),
        );
      }
      await stream.close();
    } on Object catch (error, stack) {
      await stream?.cancel();
      if (_current(generation)) _fail(error, stack);
    }
  }

  Future<void> _microphone() async {
    final generation = _begin('Checking microphone permission…');
    try {
      var permission = await MicrophonePermission.status();
      if (!_current(generation)) return;
      if (permission == MicrophonePermission.notDetermined) {
        await MicrophonePermission.request();
        permission = await MicrophonePermission.status();
      }
      if (!_current(generation)) return;
      if (permission != MicrophonePermission.authorized) {
        setState(() {
          _running = false;
          _error =
              'Microphone access is unavailable. Check the app’s '
              'microphone permission in system settings.';
        });
        return;
      }
      setState(() => _status = 'Listening. Choose Stop when finished.');
      _listen(
        SoundAnalyzer.classifyMicrophone(
          classifier: _classifier,
          maximumClassifications: 3,
        ),
        generation,
      );
    } on Object catch (error, stack) {
      if (_current(generation)) _fail(error, stack);
    }
  }

  Future<void> _stop() async {
    ++_generation;
    final subscription = _subscription;
    _subscription = null;
    final pcm = _pcm;
    _pcm = null;
    await subscription?.cancel();
    await pcm?.cancel();
    if (_alive) {
      setState(() {
        _running = false;
        _status = 'Stopped.';
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      _stop()
          .then((_) => _fixtures?.dispose())
          .catchError(
            (Object error, StackTrace stack) =>
                log('Cleanup failed', error: error, stackTrace: stack),
          ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sound Analysis')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Recognize sounds on your device',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Try bundled speech and a 550 Hz tone, feed raw audio '
                      'samples, or listen to the microphone. Nothing is uploaded.',
                    ),
                    if (!_supported)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'SoundAnalysis requires iOS 15 or macOS 12 or later.',
                        ),
                      ),
                    if (_fixtures != null) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Use the custom speech-or-tone model',
                        ),
                        subtitle: const Text(
                          'Off: Apple’s general sound classifier',
                        ),
                        value: _custom,
                        onChanged: _running
                            ? null
                            : (value) => setState(() => _custom = value),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            key: const ValueKey('speech'),
                            onPressed: _running ? null : () => _file(false),
                            child: const Text('Speech file'),
                          ),
                          FilledButton(
                            key: const ValueKey('tone'),
                            onPressed: _running ? null : () => _file(true),
                            child: const Text('Tone file'),
                          ),
                          OutlinedButton(
                            key: const ValueKey('pcm'),
                            onPressed: _running ? null : _streamPcm,
                            child: const Text('Tone as PCM'),
                          ),
                          OutlinedButton(
                            onPressed: _running ? null : _microphone,
                            child: const Text('Listen to microphone'),
                          ),
                          TextButton(
                            onPressed: _running ? _stop : null,
                            child: const Text('Stop'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(_status),
                      if (_running) const LinearProgressIndicator(),
                    ],
                    if (_error case final error?)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          error,
                          key: const ValueKey('analysis-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    for (final result in _results)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${result.startSeconds.toStringAsFixed(2)}–'
                                '${(result.startSeconds + result.durationSeconds).toStringAsFixed(2)} s',
                              ),
                              for (final classification
                                  in result.classifications)
                                Text(
                                  '${classification.identifier} '
                                  '${(classification.confidence * 100).toStringAsFixed(1)}%',
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
  );
}

import 'dart:async';

import 'package:apple_speech/apple_speech.dart';
import 'package:flutter/material.dart';

import 'fixtures.dart';

void main() => runApp(const SpeechExampleApp());

/// A demo using bundled audio and explicit permission/download actions.
class SpeechExampleApp extends StatelessWidget {
  /// [samplePath] lets widget tests supply a file without extracting assets.
  const SpeechExampleApp({super.key, this.samplePath});
  final String? samplePath;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Apple Speech',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: _SpeechPage(samplePath: samplePath),
  );
}

enum _Mode { transcriber, dictation, legacy }

class _SpeechPage extends StatefulWidget {
  const _SpeechPage({this.samplePath});
  final String? samplePath;
  @override
  State<_SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<_SpeechPage> {
  bool _loading = true;
  bool _supported = false;
  bool _analyzer = false;
  bool _transcriber = false;
  bool _version27 = false;
  bool _installed = false;
  bool _busy = false;
  _Mode _mode = _Mode.transcriber;
  String _status = 'Checking speech support…';
  String? _error;
  String _finalText = '';
  String _partialText = '';
  double? _download;
  List<TranscriptionSegment> _segments = [];
  SpeechRequest<dynamic>? _request;
  SpeechFixture? _fixture;
  Future<void>? _operation;

  List<SpeechModule> get _modules => [
    if (_mode == _Mode.dictation)
      const DictationTranscriber(
        locale: 'en-US',
        preset: DictationTranscriberPreset.timeIndexedLongDictation,
      )
    else
      const SpeechTranscriber.custom(
        locale: 'en-US',
        reportingOptions: {ReportingOption.volatileResults},
        attributeOptions: {
          ResultAttributeOption.audioTimeRange,
          ResultAttributeOption.transcriptionConfidence,
        },
      ),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supported = await Speech.isSupported();
      final analyzer = await Speech.isAnalyzerSupported();
      final transcriber = analyzer && await SpeechTranscriber.isAvailable();
      final version27 = await Speech.isVersion27Supported();
      if (!mounted) return;
      if (!analyzer) {
        _mode = _Mode.legacy;
      } else if (!transcriber && _mode == _Mode.transcriber) {
        _mode = _Mode.dictation;
      }
      final installed = !supported
          ? false
          : switch (_mode) {
              _Mode.legacy => true,
              _Mode.transcriber =>
                (await SpeechTranscriber.installedLocales()).contains('en-US'),
              _Mode.dictation =>
                (await DictationTranscriber.installedLocales()).contains(
                  'en-US',
                ),
            };
      if (!mounted) return;
      setState(() {
        _supported = supported;
        _analyzer = analyzer;
        _transcriber = transcriber;
        _version27 = version27;
        _installed = installed;
        _status = !supported
            ? 'Speech is unavailable on this platform.'
            : !installed
            ? 'English (US) speech assets are not installed.'
            : 'Ready. English (US) sample.';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _run({bool microphone = false, bool asset = false}) {
    setState(() {
      _busy = true;
      _error = null;
      _finalText = '';
      _partialText = '';
      _segments = [];
      _status = microphone ? 'Preparing microphone…' : 'Transcribing sample…';
    });
    _operation = _transcribe(microphone: microphone, asset: asset);
  }

  Future<void> _transcribe({
    required bool microphone,
    required bool asset,
  }) async {
    SpeechRequest<dynamic>? request;
    try {
      if (_mode == _Mode.legacy &&
          await SpeechRecognizer.requestAuthorization() !=
              AuthorizationStatus.authorized) {
        throw StateError(
          'Speech recognition permission was not granted. Enable it in System Settings.',
        );
      }
      if (!mounted) return;
      if (microphone &&
          await Speech.requestMicrophoneAuthorization() !=
              AuthorizationStatus.authorized) {
        throw StateError(
          'Microphone permission was not granted. Enable it in System Settings.',
        );
      }
      if (!mounted) return;
      AudioSource source;
      if (microphone) {
        source = const AudioSource.microphone();
      } else {
        if (widget.samplePath == null) _fixture ??= await SpeechFixture.load();
        if (!mounted) return;
        final path = widget.samplePath ?? _fixture!.path;
        source = asset ? AudioSource.asset(path) : AudioSource.file(path);
      }
      if (_mode == _Mode.legacy) {
        final recognition = await SpeechRecognizer.recognize(
          source: source,
          locale: 'en-US',
          requiresOnDeviceRecognition: true,
          addsPunctuation: true,
        );
        request = recognition;
        _request = recognition;
        if (!mounted) return;
        setState(
          () => _status = microphone ? 'Listening…' : 'Transcribing sample…',
        );
        await for (final result in recognition.results) {
          if (!mounted) break;
          setState(() {
            if (result.isFinal) {
              _finalText = result.bestTranscription.formattedString;
              _partialText = '';
            } else {
              _partialText = result.bestTranscription.formattedString;
            }
            _segments = result.bestTranscription.segments;
          });
        }
      } else {
        final analysis = await SpeechAnalyzer.analyze(
          source: source,
          modules: _modules,
        );
        request = analysis;
        _request = analysis;
        if (!mounted) return;
        setState(
          () => _status = microphone ? 'Listening…' : 'Transcribing sample…',
        );
        await for (final result in analysis.results) {
          if (!mounted) break;
          if (result.text == null) continue;
          setState(() {
            if (result.isFinal) {
              _finalText = '$_finalText ${result.text}'.trim();
              _partialText = '';
              _segments = [..._segments, ...result.segments];
            } else {
              _partialText = result.text!;
            }
          });
        }
      }
      if (mounted) setState(() => _status = 'Transcription complete.');
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = 'Transcription failed.';
        });
      }
    } finally {
      await request?.cancel();
      _request = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    try {
      await _request?.finish();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _download = 0;
      _error = null;
      _status = 'Downloading English speech assets…';
    });
    try {
      await AssetInventory.installAssets(
        _modules,
        onProgress: (value) {
          if (mounted) setState(() => _download = value);
        },
      );
      if (mounted) await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _download = null;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    super.dispose();
  }

  Future<void> _cleanup() async {
    try {
      await _request?.cancel();
      await _operation;
    } finally {
      await _fixture?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRun = _supported && _installed && !_loading && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apple Speech'),
        actions: [
          IconButton(
            onPressed: _busy || _loading ? null : _refresh,
            tooltip: 'Refresh availability',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Speech to text',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Transcribe a bundled English sample, inspect word timing, or listen to your microphone.',
              ),
              const SizedBox(height: 20),
              if (_loading) const LinearProgressIndicator(),
              Text(_status, key: const ValueKey('status')),
              if (!_loading && !_analyzer && _supported)
                const Text(
                  'SpeechAnalyzer needs iOS or macOS 26. The legacy recognizer is available.',
                ),
              if (!_loading && _supported) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<_Mode>(
                  isExpanded: true,
                  key: ValueKey(_mode),
                  initialValue: _mode,
                  decoration: const InputDecoration(
                    labelText: 'Recognition engine',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    if (_transcriber)
                      const DropdownMenuItem(
                        value: _Mode.transcriber,
                        child: Text('SpeechTranscriber'),
                      ),
                    if (_analyzer)
                      const DropdownMenuItem(
                        value: _Mode.dictation,
                        child: Text('DictationTranscriber'),
                      ),
                    const DropdownMenuItem(
                      value: _Mode.legacy,
                      child: Text('Legacy recognizer'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (mode) {
                          if (mode != null) {
                            setState(() => _mode = mode);
                            unawaited(_refresh());
                          }
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  _mode == _Mode.legacy
                      ? 'Legacy recognition requests speech permission when you start. This demo requires on-device recognition.'
                      : 'On-device transcription. File input needs no speech or microphone permission.',
                ),
                const SizedBox(height: 16),
                if (!_installed)
                  FilledButton.tonal(
                    key: const ValueKey('install'),
                    onPressed: _busy
                        ? null
                        : () {
                            _operation = _install();
                          },
                    child: const Text('Download English assets'),
                  ),
                if (_download != null)
                  LinearProgressIndicator(value: _download),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      key: const ValueKey('sample'),
                      onPressed: canRun ? _run : null,
                      child: const Text('Transcribe sample'),
                    ),
                    if (_version27 && _mode != _Mode.legacy)
                      OutlinedButton(
                        key: const ValueKey('asset'),
                        onPressed: canRun ? () => _run(asset: true) : null,
                        child: const Text('Read as media asset'),
                      ),
                    OutlinedButton(
                      key: const ValueKey('listen'),
                      onPressed: canRun ? () => _run(microphone: true) : null,
                      child: const Text('Listen'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('stop'),
                      onPressed: _request?.isActive == true ? _finish : null,
                      child: const Text('Stop and finalize'),
                    ),
                  ],
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SelectableText(
                    _error!,
                    key: const ValueKey('speech-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text('Transcript', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SelectableText(
                _finalText.isEmpty && _partialText.isEmpty
                    ? 'Your transcript will appear here.'
                    : '$_finalText $_partialText'.trim(),
                key: const ValueKey('transcript'),
              ),
              if (_partialText.isNotEmpty)
                const Text('In progress — words may change.'),
              const SizedBox(height: 24),
              if (_segments.isNotEmpty)
                Text(
                  'Word timing and confidence',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              for (final segment in _segments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(segment.text),
                  subtitle: Text(
                    '${_time(segment.startTime)} – ${_time(segment.endTime)}',
                  ),
                  trailing: Text(
                    segment.confidence == null
                        ? '—'
                        : '${(segment.confidence! * 100).toStringAsFixed(0)}%',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _time(Duration? time) => time == null
      ? '—'
      : '${(time.inMilliseconds / 1000).toStringAsFixed(2)} s';
}

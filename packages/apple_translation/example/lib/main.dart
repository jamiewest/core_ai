import 'dart:developer';

import 'package:apple_translation/apple_translation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const TranslationExampleApp());

/// Demonstrates translation with installed language packs.
class TranslationExampleApp extends StatelessWidget {
  /// Creates the example app.
  const TranslationExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Apple Translation',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: const _TranslationPage(),
  );
}

class _TranslationPage extends StatefulWidget {
  const _TranslationPage();

  @override
  State<_TranslationPage> createState() => _TranslationPageState();
}

class _TranslationPageState extends State<_TranslationPage> {
  final _text = TextEditingController(text: 'Hello, how are you?');
  final _results = <TranslationResponse>[];
  var _loading = true;
  var _supported = false;
  var _sessionsSupported = false;
  var _strategiesSupported = false;
  var _busy = false;
  var _checking = false;
  var _languages = <Language>[];
  var _source = 'en';
  var _target = 'es';
  TranslationStrategy? _strategy;
  LanguageStatus? _status;
  String? _error;

  bool get _controlsEnabled => !_busy && !_checking;
  bool get _canTranslate =>
      _controlsEnabled &&
      _sessionsSupported &&
      _status == LanguageStatus.installed &&
      _text.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final supported = await Translation.isSupported();
      final sessions = await Translation.isInstalledSessionSupported();
      final strategies = await Translation.isStrategySupported();
      final languages = supported
          ? await const LanguageAvailability().supportedLanguages
          : <Language>[];
      if (!mounted) return;
      setState(() {
        _supported = supported;
        _sessionsSupported = sessions;
        _strategiesSupported = strategies;
        _languages = languages;
        if (languages.isNotEmpty) {
          final ids = languages.map((language) => language.identifier);
          if (!ids.contains(_source)) _source = ids.first;
          if (!ids.contains(_target)) _target = ids.last;
        }
        _loading = false;
      });
      if (languages.isNotEmpty) await _checkPair();
    } on Object catch (error, stack) {
      _showError(error, stack);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object error, StackTrace stack) {
    log('Translation failed', error: error, stackTrace: stack);
    if (!mounted) return;
    setState(() {
      _error = error is TranslationException ? error.message : '$error';
    });
  }

  Future<void> _checkPair() async {
    setState(() {
      _checking = true;
      _status = null;
      _error = null;
      _results.clear();
    });
    try {
      final status = await LanguageAvailability(
        preferredStrategy: _strategy,
      ).status(from: _source, to: _target);
      if (mounted) setState(() => _status = status);
    } on Object catch (error, stack) {
      _showError(error, stack);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _translate({bool batch = false}) async {
    if (!_canTranslate) return;
    final text = _text.text;
    setState(() {
      _busy = true;
      _error = null;
      _results.clear();
    });
    try {
      final session = await TranslationSession.create(
        installedSource: _source,
        target: _target,
        preferredStrategy: _strategy,
      );
      try {
        if (batch) {
          final lines = text
              .split('\n')
              .where((line) => line.trim().isNotEmpty);
          final requests = [
            for (final (index, line) in lines.indexed)
              TranslationRequest(line, clientIdentifier: '${index + 1}'),
          ];
          await for (final response in session.translateBatch(requests)) {
            if (mounted) setState(() => _results.add(response));
          }
        } else {
          final response = await session.translate(text);
          if (mounted) setState(() => _results.add(response));
        }
      } finally {
        await session.dispose();
      }
    } on Object catch (error, stack) {
      _showError(error, stack);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _languageField({required bool source}) =>
      DropdownButtonFormField<String>(
        key: ValueKey(source ? 'source-language' : 'target-language'),
        initialValue: source ? _source : _target,
        isExpanded: true,
        decoration: InputDecoration(labelText: source ? 'From' : 'To'),
        items: [
          for (final language in _languages)
            DropdownMenuItem(
              value: language.identifier,
              child: Text(
                '${language.localizedName ?? language.identifier} '
                '(${language.identifier})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: !_controlsEnabled
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  if (source) {
                    _source = value;
                  } else {
                    _target = value;
                  }
                });
                _checkPair();
              },
      );

  String get _statusText => switch (_status) {
    LanguageStatus.installed => 'Language packs installed. Ready to translate.',
    LanguageStatus.supported =>
      'Download these languages in your device’s translation language settings, '
          'then check again. This app uses installed packs only.',
    LanguageStatus.unsupported =>
      'This language pair is not supported. Choose different languages.',
    null =>
      _checking ? 'Checking language packs…' : 'Language status unavailable.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Apple Translation')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Translate on your device',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose the language your text is written in and where '
                      'to translate it. No account or API key is needed.',
                    ),
                    if (!_supported)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Apple Translation requires iOS 18 or macOS 15 '
                          'or later.',
                        ),
                      )
                    else if (!_sessionsSupported)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Language checks are available, but translating '
                          'in this app requires iOS 26 or macOS 26 or later.',
                        ),
                      ),
                    if (_languages.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _languageField(source: true),
                      const SizedBox(height: 16),
                      _languageField(source: false),
                      if (_strategiesSupported) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<TranslationStrategy>(
                          initialValue: _strategy,
                          decoration: const InputDecoration(
                            labelText: 'Translation model',
                          ),
                          hint: const Text('System default'),
                          items: const [
                            DropdownMenuItem(
                              value: TranslationStrategy.highFidelity,
                              child: Text('Best quality'),
                            ),
                            DropdownMenuItem(
                              value: TranslationStrategy.lowLatency,
                              child: Text('Faster translation'),
                            ),
                          ],
                          onChanged: !_controlsEnabled
                              ? null
                              : (value) {
                                  setState(() => _strategy = value);
                                  _checkPair();
                                },
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(_statusText),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _controlsEnabled ? _checkPair : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Check language packs'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const ValueKey('source-text'),
                        controller: _text,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 8,
                        onChanged: (_) => setState(_results.clear),
                        decoration: const InputDecoration(
                          labelText: 'Text to translate',
                          border: OutlineInputBorder(),
                          helperText:
                              'For a batch, put each phrase on its own line.',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            key: const ValueKey('translate'),
                            onPressed: _canTranslate ? _translate : null,
                            child: const Text('Translate'),
                          ),
                          OutlinedButton(
                            key: const ValueKey('translate-lines'),
                            onPressed: _canTranslate
                                ? () => _translate(batch: true)
                                : null,
                            child: const Text('Translate each line'),
                          ),
                        ],
                      ),
                      if (_busy) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                    ],
                    if (_error case final error?) ...[
                      const SizedBox(height: 16),
                      Text(
                        error,
                        key: const ValueKey('translation-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    for (final response in _results) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                response.clientIdentifier == null
                                    ? response.sourceText
                                    : 'Line ${response.clientIdentifier}: ${response.sourceText}',
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                response.targetText,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
  );
}

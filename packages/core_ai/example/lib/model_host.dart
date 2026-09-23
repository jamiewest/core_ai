import 'dart:developer' as developer;

import 'package:core_ai/core_ai.dart';
import 'package:flutter/material.dart';

import 'demos.dart';

/// Loads [demo]'s model with [options], shows its signature, and hosts the
/// demo's controls. Disposes the native function when removed.
class ModelHost extends StatefulWidget {
  const ModelHost({super.key, required this.demo, required this.options});

  final ModelDemo demo;
  final SpecializationOptions options;

  @override
  State<ModelHost> createState() => _ModelHostState();
}

class _ModelHostState extends State<ModelHost> {
  late final Future<(InferenceFunction, Duration)> _loading = _load();
  InferenceFunction? _function;

  Future<(InferenceFunction, Duration)> _load() async {
    final watch = Stopwatch()..start();
    final model = await AIModel.loadAsset(
      widget.demo.asset,
      options: widget.options,
    );
    try {
      final function = await model.loadFunction();
      if (!mounted) {
        await function.dispose();
      } else {
        _function = function;
      }
      return (function, watch.elapsed);
    } finally {
      // The function keeps its own resources; the model is no longer needed.
      await model.dispose();
    }
  }

  @override
  void dispose() {
    _function?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(InferenceFunction, Duration)>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            developer.log(
              'Failed to load ${widget.demo.asset}',
              name: 'core_ai_example',
              error: snapshot.error,
            );
            return _ErrorCard(error: snapshot.error!);
          }
          final loaded = snapshot.data;
          if (loaded == null) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final (function, loadTime) = loaded;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SignatureCard(
                demo: widget.demo,
                descriptor: function.descriptor,
                loadTime: loadTime,
              ),
              const SizedBox(height: 16),
              widget.demo.builder(function),
            ],
          );
        },
      );
}

class _SignatureCard extends StatelessWidget {
  const _SignatureCard({
    required this.demo,
    required this.descriptor,
    required this.loadTime,
  });

  final ModelDemo demo;
  final FunctionDescriptor descriptor;
  final Duration loadTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String label, Map<String, ValueDescriptor> values) {
      if (values.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            for (final value in values.values)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(_describe(value)),
              ),
          ],
        ),
      );
    }

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(demo.title, style: theme.textTheme.titleLarge),
            Text(demo.description),
            const SizedBox(height: 4),
            Text(
              'Loaded "${descriptor.name}" in ${loadTime.inMilliseconds} ms',
              style: theme.textTheme.bodySmall,
            ),
            section('Inputs', descriptor.inputs),
            section('States', descriptor.states),
            section('Outputs', descriptor.outputs),
          ],
        ),
      ),
    );
  }

  static String _describe(ValueDescriptor value) => switch (value) {
    NDArrayDescriptor(:final name, :final scalarType, :final shape) =>
      '$name: ${scalarType.name} $shape',
    ImageDescriptor(:final name, :final width, :final height) =>
      '$name: ${width}x$height '
          '${PixelFormat.describe(value.pixelFormatType)}',
  };
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('$error', style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

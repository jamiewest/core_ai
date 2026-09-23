import 'dart:developer';
import 'dart:typed_data';

import 'package:core_ml/core_ml.dart';
import 'package:flutter/material.dart';

/// One runnable demo: a title, a description and an action producing text.
class Demo {
  /// Creates a demo.
  const Demo(this.title, this.subtitle, this.icon, this.run);

  /// The card title.
  final String title;

  /// What the demo shows.
  final String subtitle;

  /// The card icon.
  final IconData icon;

  /// Runs the demo and returns a description of the result.
  final Future<String> Function() run;
}

/// The demos, each against one bundled model.
final demos = <Demo>[
  Demo(
    'Affine',
    'Compile affine.mlpackage, then predict y = 2x + 1',
    Icons.functions,
    () => _withModel('affine', (model) async {
      final prediction = await model.predict({
        'x': MLMultiArray.float32([1, 2, 3]),
      });
      return 'x = [1, 2, 3]\ny = ${prediction.multiArray('y').toDoubleList()}';
    }),
  ),
  Demo(
    'Multiple outputs',
    'y = a @ b + c and a + 1 from multi_io.mlpackage',
    Icons.call_split,
    () => _withModel('multi_io', (model) async {
      final prediction = await model.predict({
        'a': MLMultiArray.float32([0, 1, 2, 3, 4, 5], shape: [2, 3]),
        'b': MLMultiArray.float32(List.filled(6, 1), shape: [3, 2]),
        'c': MLMultiArray.float32(List.filled(4, 0.5), shape: [2, 2]),
      });
      return 'y = ${prediction.multiArray('y').toDoubleList()}\n'
          'a_plus_1 = ${prediction.multiArray('a_plus_1').toDoubleList()}';
    }),
  ),
  Demo(
    'Classifier',
    'Class label and probabilities from classifier.mlpackage',
    Icons.label,
    () => _withModel('classifier', (model) async {
      final prediction = await model.predict({
        'scores': MLMultiArray.float32([0, 5, 1], shape: [1, 3]),
      });
      final probabilities = prediction
          .dictionary('classLabel_probs')
          .stringKeyed!
          .entries
          .map((e) => '${e.key}: ${e.value.toStringAsFixed(3)}')
          .join(', ');
      return 'labels: ${model.modelDescription.classLabels}\n'
          'predicted: ${prediction.stringValue('classLabel')}\n'
          '$probabilities';
    }),
  ),
  Demo(
    'Image input',
    'Encode a PNG, let Core ML read it through image_input.mlpackage',
    Icons.image,
    () => _withModel('image_input', (model) async {
      final png = await CoreML.encodeImage(
        PixelBuffer.packed(
          width: 32,
          height: 32,
          pixelFormatType: PixelFormat.bgra32,
          bytes: Uint8List.fromList([
            for (var i = 0; i < 32 * 32; i++) ...[200, 120, 40, 255],
          ]),
        ),
      );
      final constraint =
          model.modelDescription.inputs['image']!.imageConstraint!;
      final prediction = await model.predict({
        'image': ImageInput.encoded(png),
      });
      final pixels = prediction.multiArray('pixels').toDoubleList();
      return 'input constraint: $constraint '
          '${PixelFormat.describe(constraint.pixelFormatType)}\n'
          'B, G, R at (0, 0): '
          '${[pixels[0], pixels[16], pixels[32]]}';
    }),
  ),
  Demo(
    'Stateful model',
    'MLState accumulates x across predictions (stateful.mlpackage)',
    Icons.history,
    () => _withModel('stateful', (model) async {
      final state = await model.makeState();
      try {
        final lines = <String>[];
        for (var step = 1; step <= 3; step++) {
          final prediction = await model.predict({
            'x': MLMultiArray.float16([1, 2, 3]),
          }, state: state);
          lines.add('step $step: ${prediction.multiArray('y').toDoubleList()}');
        }
        lines.add('state: ${(await state.read('total')).toDoubleList()}');
        return lines.join('\n');
      } finally {
        await state.dispose();
      }
    }),
  ),
  Demo(
    'Batch and compute units',
    'Batch prediction on each MLComputeUnits setting',
    Icons.memory,
    () async {
      final devices = await CoreML.availableComputeDevices();
      final lines = ['devices: ${devices.join(', ')}'];
      for (final units in MLComputeUnits.values) {
        final model = await MLModel.loadAsset(
          'assets/models/affine.mlpackage',
          configuration: MLModelConfiguration(computeUnits: units),
        );
        try {
          final results = await model.predictBatch([
            for (var i = 0; i < 3; i++)
              {
                'x': MLMultiArray.float32([i, i, i]),
              },
          ]);
          final ys = results.map((r) => r.multiArray('y').toDoubleList()[0]);
          lines.add('${units.name}: ${ys.toList()}');
        } finally {
          await model.dispose();
        }
      }
      return lines.join('\n');
    },
  ),
];

Future<String> _withModel(
  String name,
  Future<String> Function(MLModel model) body,
) async {
  final model = await MLModel.loadAsset('assets/models/$name.mlpackage');
  try {
    final metadata = model.modelDescription.metadata;
    final result = await body(model);
    return metadata.description == null
        ? result
        : '${metadata.description}\n$result';
  } finally {
    await model.dispose();
  }
}

/// Lists the demos, or explains why Core ML is unavailable.
class HomePage extends StatefulWidget {
  /// Creates the page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool? _supported;
  String _platform = '';

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    final supported = await CoreML.isSupported();
    final platform = await CoreML.platformVersion().catchError((_) => '');
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _platform = platform;
    });
  }

  @override
  Widget build(BuildContext context) {
    final supported = _supported;
    return Scaffold(
      appBar: AppBar(title: const Text('core_ml')),
      body: switch (supported) {
        null => const Center(child: CircularProgressIndicator()),
        false => _UnsupportedNotice(platform: _platform),
        true => ListView(
          padding: const EdgeInsets.all(12),
          children: [for (final demo in demos) _DemoCard(demo: demo)],
        ),
      },
    );
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'core_ml needs iOS 18 or macOS 15 or later.\n$platform',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

class _DemoCard extends StatefulWidget {
  const _DemoCard({required this.demo});

  final Demo demo;

  @override
  State<_DemoCard> createState() => _DemoCardState();
}

class _DemoCardState extends State<_DemoCard> {
  bool _running = false;
  String? _output;

  Future<void> _run() async {
    setState(() => _running = true);
    String output;
    try {
      output = await widget.demo.run();
    } on Object catch (error, stackTrace) {
      log('Demo failed', name: 'core_ml', error: error, stackTrace: stackTrace);
      output = 'Error: $error';
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _output = output;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final output = _output;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(widget.demo.icon),
              title: Text(widget.demo.title),
              subtitle: Text(widget.demo.subtitle),
              trailing: FilledButton(
                onPressed: _running ? null : _run,
                child: _running
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Run'),
              ),
            ),
            if (output != null)
              SelectableText(
                output,
                style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'),
              ),
          ],
        ),
      ),
    );
  }
}

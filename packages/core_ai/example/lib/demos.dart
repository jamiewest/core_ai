import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_ai/core_ai.dart';
import 'package:flutter/material.dart';

/// A bundled model and the widget that exercises it.
class ModelDemo {
  const ModelDemo({
    required this.title,
    required this.icon,
    required this.asset,
    required this.description,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final String asset;
  final String description;
  final Widget Function(InferenceFunction function) builder;
}

final List<ModelDemo> modelDemos = [
  ModelDemo(
    title: 'Affine',
    icon: Icons.functions,
    asset: 'assets/models/affine.aimodel',
    description: 'Computes y = 2x + 1 on a float32 [3] array.',
    builder: (function) => _AffineDemo(function: function),
  ),
  ModelDemo(
    title: 'Stateful',
    icon: Icons.stacked_line_chart,
    asset: 'assets/models/accumulator.aimodel',
    description:
        'Adds x into a state that stays on the native side between runs, '
        'the way a language model keeps its key-value cache.',
    builder: (function) => _AccumulatorDemo(function: function),
  ),
  ModelDemo(
    title: 'Image',
    icon: Icons.image_outlined,
    asset: 'assets/models/image_to_tensor.aimodel',
    description:
        'Turns a 4x4 BGRA pixel buffer into a float32 [4, 4, 4] tensor.',
    builder: (function) => _ImageDemo(function: function),
  ),
  ModelDemo(
    title: 'Matmul',
    icon: Icons.grid_on,
    asset: 'assets/models/matmul_add.aimodel',
    description:
        'Computes y = a·b + c and a + 1: three inputs, two outputs. Run it '
        'directly or encode it on a ComputeStream.',
    builder: (function) => _MatmulDemo(function: function),
  ),
];

/// Runs [body], timing it and capturing errors for display.
Future<String> _timed(Future<String> Function() body) async {
  final watch = Stopwatch()..start();
  try {
    final result = await body();
    return '$result\n\n${watch.elapsedMicroseconds / 1000} ms';
  } on CoreAIException catch (error) {
    return 'Error: $error';
  }
}

String _format(Iterable<double> values) =>
    '[${values.map((v) => v.toStringAsFixed(2)).join(', ')}]';

class _AffineDemo extends StatefulWidget {
  const _AffineDemo({required this.function});

  final InferenceFunction function;

  @override
  State<_AffineDemo> createState() => _AffineDemoState();
}

class _AffineDemoState extends State<_AffineDemo> {
  final _input = TextEditingController(text: '1, 2, 3');
  String? _result;

  Future<void> _run() async {
    final values = _input.text
        .split(',')
        .map((part) => double.tryParse(part.trim()))
        .toList();
    if (values.length != 3 || values.contains(null)) {
      setState(() => _result = 'Enter exactly three numbers.');
      return;
    }
    final result = await _timed(() async {
      final outputs = await widget.function.run({
        'x': NDArray.float32(values.cast<double>()),
      });
      return 'y = ${_format(outputs.ndArray('y').toDoubleList())}';
    });
    if (mounted) setState(() => _result = result);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DemoCard(
    result: _result,
    children: [
      TextField(
        controller: _input,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(
          labelText: 'x (three numbers)',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _run(),
      ),
      FilledButton.icon(
        onPressed: _run,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Run'),
      ),
    ],
  );
}

class _AccumulatorDemo extends StatefulWidget {
  const _AccumulatorDemo({required this.function});

  final InferenceFunction function;

  @override
  State<_AccumulatorDemo> createState() => _AccumulatorDemoState();
}

class _AccumulatorDemoState extends State<_AccumulatorDemo> {
  late final Future<InferenceState> _state = widget.function.makeState();
  var _steps = 0;
  String? _result;

  Future<void> _step() async {
    final state = await _state;
    final result = await _timed(() async {
      final outputs = await widget.function.run({
        'x': NDArray.float32([1, 2, 3]),
      }, state: state);
      _steps++;
      return 'After $_steps step(s): total = '
          '${_format(outputs.ndArray('y').toDoubleList())}';
    });
    if (mounted) setState(() => _result = result);
  }

  Future<void> _reset() async {
    await (await _state).reset();
    if (!mounted) return;
    setState(() {
      _steps = 0;
      _result = 'State reset to zeros.';
    });
  }

  @override
  void dispose() {
    _state.then((state) => state.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DemoCard(
    result: _result,
    children: [
      FilledButton.icon(
        onPressed: _step,
        icon: const Icon(Icons.add),
        label: const Text('Add x = [1, 2, 3]'),
      ),
      OutlinedButton.icon(
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset state'),
      ),
    ],
  );
}

class _ImageDemo extends StatefulWidget {
  const _ImageDemo({required this.function});

  final InferenceFunction function;

  @override
  State<_ImageDemo> createState() => _ImageDemoState();
}

class _ImageDemoState extends State<_ImageDemo> {
  static const _colors = [
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFFFDD835),
    Color(0xFF8E24AA),
  ];

  Color _color = _colors.first;
  String? _result;

  Future<void> _run(Color color) async {
    setState(() => _color = color);
    final (r, g, b) = (
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
    );
    final rgba = Uint8List(4 * 4 * 4);
    for (var pixel = 0; pixel < 16; pixel++) {
      rgba.setAll(pixel * 4, [r, g, b, 255]);
    }
    final result = await _timed(() async {
      final image = PixelBuffer.fromRgba8888(rgba, width: 4, height: 4);
      final outputs = await widget.function.run({'image': image});
      final pixels = outputs.ndArray('pixels');
      return 'RGB ($r, $g, $b) as a 4x4 BGRA pixel buffer\n'
          'pixels ${pixels.shape}, first pixel (B, G, R, A) = '
          '${_format(pixels.toDoubleList().take(4))}';
    });
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) => _DemoCard(
    result: _result,
    children: [
      Wrap(
        spacing: 12,
        children: [
          for (final color in _colors)
            _Swatch(
              color: color,
              selected: color == _color,
              onTap: () => _run(color),
            ),
        ],
      ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Run with this color',
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            width: selected ? 4 : 1,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    ),
  );
}

class _MatmulDemo extends StatefulWidget {
  const _MatmulDemo({required this.function});

  final InferenceFunction function;

  @override
  State<_MatmulDemo> createState() => _MatmulDemoState();
}

class _MatmulDemoState extends State<_MatmulDemo> {
  final _random = math.Random();
  String? _result;

  Map<String, NDArray> _inputs() {
    List<double> values(int count) => [
      for (var i = 0; i < count; i++) _random.nextInt(5).toDouble(),
    ];
    return {
      'a': NDArray.float32(values(6), shape: [2, 3]),
      'b': NDArray.float32(values(6), shape: [3, 2]),
      'c': NDArray.float32(values(4), shape: [2, 2]),
    };
  }

  static String _matrix(NDArray array) {
    final values = array.toDoubleList();
    final columns = array.shape.last;
    return [
      for (var row = 0; row < values.length ~/ columns; row++)
        _format(values.skip(row * columns).take(columns)),
    ].join('\n');
  }

  Future<void> _run({required bool encode}) async {
    final inputs = _inputs();
    final result = await _timed(() async {
      final NDArray y;
      final NDArray aPlus1;
      if (encode) {
        final stream = await ComputeStream.create();
        final outputs = await widget.function.encode(inputs, stream: stream);
        y = await outputs['y']!.readNDArray();
        aPlus1 = await outputs['a_plus_1']!.readNDArray();
        await Future.wait([
          ...outputs.values.map((value) => value.dispose()),
          stream.dispose(),
        ]);
      } else {
        final outputs = await widget.function.run(inputs);
        y = outputs.ndArray('y');
        aPlus1 = outputs.ndArray('a_plus_1');
      }
      return 'a =\n${_matrix(inputs['a']!)}\n'
          'b =\n${_matrix(inputs['b']!)}\n'
          'c =\n${_matrix(inputs['c']!)}\n'
          'y = a·b + c =\n${_matrix(y)}\n'
          'a + 1 =\n${_matrix(aPlus1)}';
    });
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) => _DemoCard(
    result: _result,
    children: [
      FilledButton.icon(
        onPressed: () => _run(encode: false),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Run with random inputs'),
      ),
      OutlinedButton.icon(
        onPressed: () => _run(encode: true),
        icon: const Icon(Icons.stream),
        label: const Text('Encode on a ComputeStream'),
      ),
    ],
  );
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.children, this.result});

  final List<Widget> children;
  final String? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                result!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'Menlo',
                  fontFamilyFallback: const ['Courier', 'monospace'],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:developer';
import 'dart:typed_data';

import 'package:apple_vision/apple_vision.dart';
import 'package:flutter/material.dart';

void main() => runApp(const VisionDemoApp());

/// Demonstrates the main apple_vision requests on bundled images.
class VisionDemoApp extends StatelessWidget {
  /// Creates the demo app.
  const VisionDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: 'Apple Vision',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const VisionDemoPage(),
    );
  }
}

/// The sample images bundled with the example.
const _samples = {
  'Text': 'assets/ocr_text.png',
  'QR code': 'assets/qr_code.png',
  'Rectangle': 'assets/shapes.png',
  'Document': 'assets/document.png',
};

/// Runs a batch of requests on the selected sample and shows the results.
class VisionDemoPage extends StatefulWidget {
  /// Creates the page.
  const VisionDemoPage({super.key});

  @override
  State<VisionDemoPage> createState() => _VisionDemoPageState();
}

class _VisionDemoPageState extends State<VisionDemoPage> {
  static const _text = RecognizeTextRequest();
  static const _barcodes = DetectBarcodesRequest();
  static const _rectangles = DetectRectanglesRequest(minimumSize: 0.2);
  static const _classify = ClassifyImageRequest();
  static const _saliency = GenerateAttentionBasedSaliencyImageRequest();
  static const _faces = DetectFaceRectanglesRequest();

  bool? _supported;
  String _sample = _samples.keys.first;
  bool _busy = false;
  VisionAnalysis? _analysis;
  Uint8List? _heatMapPng;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    final supported = await AppleVision.isSupported();
    if (!mounted) return;
    setState(() => _supported = supported);
    if (supported) await _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await ImageInput.asset(_samples[_sample]!);
      final analysis = await AppleVision.analyze(
        image,
        requests: const [
          _text,
          _barcodes,
          _rectangles,
          _classify,
          _saliency,
          _faces,
        ],
      );
      final png = analysis.succeeded(_saliency)
          ? await analysis.resultOf(_saliency).heatMap.toPng()
          : null;
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _heatMapPng = png;
      });
    } on AppleVisionException catch (error) {
      log('Analysis failed', error: error, name: 'apple_vision_example');
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = _supported;
    return Scaffold(
      appBar: AppBar(title: const Text('Apple Vision')),
      body: switch (supported) {
        null => const Center(child: CircularProgressIndicator()),
        false => const _UnsupportedNotice(),
        true => _buildContent(context),
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final analysis = _analysis;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: [
            for (final name in _samples.keys)
              ButtonSegment(value: name, label: Text(name)),
          ],
          selected: {_sample},
          onSelectionChanged: _busy
              ? null
              : (selection) {
                  setState(() => _sample = selection.single);
                  _analyze();
                },
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        _AnnotatedImage(
          asset: _samples[_sample]!,
          analysis: analysis,
          quads: [
            if (analysis != null && analysis.succeeded(_text))
              for (final line in analysis.resultOf(_text)) line.quad,
            if (analysis != null && analysis.succeeded(_barcodes))
              for (final code in analysis.resultOf(_barcodes)) code.quad,
            if (analysis != null && analysis.succeeded(_rectangles))
              ...analysis.resultOf(_rectangles),
          ],
        ),
        if (analysis != null) ..._results(context, analysis),
      ],
    );
  }

  List<Widget> _results(BuildContext context, VisionAnalysis analysis) {
    String describe<R>(VisionRequest<R> request, String Function(R) format) {
      final error = analysis.errorFor(request);
      return error != null
          ? 'Failed: ${error.message}'
          : format(analysis.resultOf(request));
    }

    return [
      _ResultTile(
        icon: Icons.text_fields,
        title: 'Recognized text',
        body: describe(
          _text,
          (lines) => lines.isEmpty
              ? 'No text'
              : lines.map((line) => line.text).join('\n'),
        ),
      ),
      _ResultTile(
        icon: Icons.qr_code,
        title: 'Barcodes',
        body: describe(
          _barcodes,
          (codes) => codes.isEmpty
              ? 'No barcodes'
              : codes
                    .map((code) => '${code.symbology.name}: ${code.payload}')
                    .join('\n'),
        ),
      ),
      _ResultTile(
        icon: Icons.crop_square,
        title: 'Rectangles',
        body: describe(_rectangles, (quads) => '${quads.length} found'),
      ),
      _ResultTile(
        icon: Icons.label_outline,
        title: 'Classification',
        body: describe(
          _classify,
          (labels) => labels
              .take(5)
              .map(
                (label) =>
                    '${label.identifier} '
                    '${(label.confidence * 100).toStringAsFixed(0)}%',
              )
              .join(', '),
        ),
      ),
      _ResultTile(
        icon: Icons.face,
        title: 'Faces',
        body: describe(_faces, (faces) => '${faces.length} found'),
      ),
      if (_heatMapPng != null)
        _ResultTile(
          icon: Icons.visibility,
          title: 'Attention heat map',
          body: describe(_saliency, (saliency) => '${saliency.heatMap}'),
          trailing: Image.memory(
            _heatMapPng!,
            width: 68,
            height: 68,
            filterQuality: FilterQuality.none,
          ),
        ),
    ];
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Apple Vision needs iOS 27 or macOS 27 or later.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _AnnotatedImage extends StatelessWidget {
  const _AnnotatedImage({
    required this.asset,
    required this.analysis,
    required this.quads,
  });

  final String asset;
  final VisionAnalysis? analysis;
  final List<NormalizedQuad> quads;

  @override
  Widget build(BuildContext context) {
    final size = analysis?.imageSize;
    return AspectRatio(
      aspectRatio: size == null ? 4 / 3 : size.width / size.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(asset, fit: BoxFit.fill),
          CustomPaint(
            painter: _QuadPainter(quads, Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

/// Draws Vision quads, converting from Vision's lower-left origin.
class _QuadPainter extends CustomPainter {
  _QuadPainter(this.quads, this.color);

  final List<NormalizedQuad> quads;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final quad in quads) {
      final corners = quad.toImageCoordinates(size);
      canvas.drawPath(Path()..addPolygon(corners, true), paint);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.quads != quads || oldDelegate.color != color;
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(body),
    trailing: trailing,
  );
}

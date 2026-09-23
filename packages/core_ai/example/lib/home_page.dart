import 'package:core_ai/core_ai.dart';
import 'package:flutter/material.dart';

import 'demos.dart';
import 'model_host.dart';

/// Device information, a model picker and the selected model's demo.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<_DeviceInfo> _device = _DeviceInfo.load();
  ModelDemo _demo = modelDemos.first;
  SpecializationOptions _options = SpecializationOptions.defaults;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Core AI')),
    body: FutureBuilder<_DeviceInfo>(
      future: _device,
      builder: (context, snapshot) {
        final device = snapshot.data;
        if (device == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!device.supported) return _UnsupportedNotice(device: device);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DeviceCard(device: device),
            const SizedBox(height: 16),
            _DemoPicker(
              selected: _demo,
              onSelected: (demo) => setState(() => _demo = demo),
            ),
            const SizedBox(height: 12),
            _OptionsPicker(
              selected: _options,
              onSelected: (options) => setState(() => _options = options),
            ),
            const SizedBox(height: 16),
            ModelHost(
              key: ValueKey((_demo, _options)),
              demo: _demo,
              options: _options,
            ),
          ],
        );
      },
    ),
  );
}

class _DeviceInfo {
  const _DeviceInfo({
    required this.supported,
    required this.platform,
    this.architecture,
    this.computeUnits = const {},
  });

  static Future<_DeviceInfo> load() async {
    final supported = await CoreAI.isSupported();
    final platform = await CoreAI.platformVersion().catchError(
      (Object _) => 'unknown platform',
    );
    if (!supported) return _DeviceInfo(supported: false, platform: platform);
    return _DeviceInfo(
      supported: true,
      platform: platform,
      architecture: await CoreAI.deviceArchitectureName(),
      computeUnits: await CoreAI.availableComputeUnitKinds(),
    );
  }

  final bool supported;
  final String platform;
  final String? architecture;
  final Set<ComputeUnitKind> computeUnits;
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final _DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.memory,
              size: 40,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.platform, style: theme.textTheme.titleMedium),
                  Text('Architecture: ${device.architecture}'),
                  Text(
                    'Compute units: '
                    '${device.computeUnits.map((k) => k.name).join(', ')}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice({required this.device});

  final _DeviceInfo device;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, size: 48),
          const SizedBox(height: 16),
          Text(
            'Core AI is not available on ${device.platform}.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'It needs macOS 27 or an iOS 27 device. The iOS Simulator does '
            'not include Core AI.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _DemoPicker extends StatelessWidget {
  const _DemoPicker({required this.selected, required this.onSelected});

  final ModelDemo selected;
  final ValueChanged<ModelDemo> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<ModelDemo>(
      segments: [
        for (final demo in modelDemos)
          ButtonSegment(
            value: demo,
            label: Text(demo.title),
            icon: Icon(demo.icon),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onSelected(selection.single),
    ),
  );
}

class _OptionsPicker extends StatelessWidget {
  const _OptionsPicker({required this.selected, required this.onSelected});

  final SpecializationOptions selected;
  final ValueChanged<SpecializationOptions> onSelected;

  static const _choices = {
    'All compute units': SpecializationOptions.defaults,
    'CPU only': SpecializationOptions.cpuOnly,
    'Prefer GPU': SpecializationOptions.preferring(ComputeUnitKind.gpu),
    'Prefer Neural Engine': SpecializationOptions.preferring(
      ComputeUnitKind.neuralEngine,
    ),
  };

  @override
  Widget build(BuildContext context) => DropdownMenu<SpecializationOptions>(
    label: const Text('Specialization'),
    initialSelection: selected,
    onSelected: (options) {
      if (options != null) onSelected(options);
    },
    dropdownMenuEntries: [
      for (final MapEntry(:key, :value) in _choices.entries)
        DropdownMenuEntry(value: value, label: key),
    ],
  );
}

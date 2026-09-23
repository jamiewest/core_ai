import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

/// A kind of hardware compute unit (Core AI's `ComputeUnitKind`).
enum ComputeUnitKind {
  /// The CPU.
  cpu,

  /// The GPU.
  gpu,

  /// The Neural Engine.
  neuralEngine;

  /// The Pigeon representation.
  ComputeUnitKindMessage toMessage() => ComputeUnitKindMessage.values[index];

  /// Converts from the Pigeon representation.
  static ComputeUnitKind fromMessage(ComputeUnitKindMessage message) =>
      values[message.index];
}

enum _Preset { defaults, cpuOnly, preferred }

/// Controls how a model is specialized for the device (Core AI's
/// `SpecializationOptions`).
///
/// Each distinct set of options produces its own entry in the specialized
/// model cache.
@immutable
final class SpecializationOptions {
  const SpecializationOptions._(
    this._preset,
    this.preferredComputeUnitKind, {
    this.expectFrequentReshapes = false,
  });

  /// Prefers [kind], falling back to other compute units for incompatible
  /// operations.
  const SpecializationOptions.preferring(
    ComputeUnitKind kind, {
    bool expectFrequentReshapes = false,
  }) : this._(
         _Preset.preferred,
         kind,
         expectFrequentReshapes: expectFrequentReshapes,
       );

  /// Uses all available compute units, choosing whatever minimizes latency.
  static const SpecializationOptions defaults = SpecializationOptions._(
    _Preset.defaults,
    null,
  );

  /// Restricts inference to the CPU.
  static const SpecializationOptions cpuOnly = SpecializationOptions._(
    _Preset.cpuOnly,
    null,
  );

  final _Preset _preset;

  /// The preferred compute unit, when created with [preferring].
  final ComputeUnitKind? preferredComputeUnitKind;

  /// Whether to optimize for models that are frequently run with different
  /// input shapes.
  final bool expectFrequentReshapes;

  /// A copy with [expectFrequentReshapes] replaced.
  SpecializationOptions copyWith({bool? expectFrequentReshapes}) =>
      SpecializationOptions._(
        _preset,
        preferredComputeUnitKind,
        expectFrequentReshapes:
            expectFrequentReshapes ?? this.expectFrequentReshapes,
      );

  /// Asks Core AI which compute units these options allow on this device.
  Future<SpecializationInfo> resolve() async {
    final host = CoreAIBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.describeSpecializationOptions(toMessage()),
    );
    return SpecializationInfo(
      allowedComputeUnitKinds: {
        for (final kind in info.allowedComputeUnitKinds)
          ComputeUnitKind.fromMessage(kind),
      },
      preferredComputeUnitKind: switch (info.preferredComputeUnitKind) {
        final kind? => ComputeUnitKind.fromMessage(kind),
        null => null,
      },
      expectFrequentReshapes: info.expectFrequentReshapes,
    );
  }

  /// The Pigeon representation.
  SpecializationOptionsMessage toMessage() => SpecializationOptionsMessage(
    preset: SpecializationPresetMessage.values[_preset.index],
    preferredComputeUnitKind: preferredComputeUnitKind?.toMessage(),
    expectFrequentReshapes: expectFrequentReshapes,
  );

  @override
  bool operator ==(Object other) =>
      other is SpecializationOptions &&
      other._preset == _preset &&
      other.preferredComputeUnitKind == preferredComputeUnitKind &&
      other.expectFrequentReshapes == expectFrequentReshapes;

  @override
  int get hashCode =>
      Object.hash(_preset, preferredComputeUnitKind, expectFrequentReshapes);

  @override
  String toString() {
    final base = switch (_preset) {
      _Preset.defaults => 'defaults',
      _Preset.cpuOnly => 'cpuOnly',
      _Preset.preferred => 'preferring(${preferredComputeUnitKind!.name})',
    };
    return 'SpecializationOptions.$base'
        '${expectFrequentReshapes ? ', expectFrequentReshapes' : ''}';
  }
}

/// What a [SpecializationOptions] resolves to on this device.
@immutable
final class SpecializationInfo {
  /// Creates an info object.
  const SpecializationInfo({
    required this.allowedComputeUnitKinds,
    required this.preferredComputeUnitKind,
    required this.expectFrequentReshapes,
  });

  /// The compute units the specialized model may use.
  final Set<ComputeUnitKind> allowedComputeUnitKinds;

  /// The preferred compute unit, if any.
  final ComputeUnitKind? preferredComputeUnitKind;

  /// Whether frequent reshapes are expected.
  final bool expectFrequentReshapes;

  @override
  String toString() =>
      'SpecializationInfo(allowed: '
      '${allowedComputeUnitKinds.map((k) => k.name).toList()}, preferred: '
      '${preferredComputeUnitKind?.name})';
}

/// When the system may purge a specialized model from the cache (Core AI's
/// `AIModelCache.Policy`). Assets are always purged on OS updates.
@immutable
final class CachePolicy {
  /// Creates a policy with explicit purge conditions.
  const CachePolicy({
    this.purgeOnStoragePressure = true,
    this.purgeOnSourceAssetChangedOrDeleted = true,
  });

  /// Purgeable under storage pressure or when the source model changes.
  static const CachePolicy defaults = CachePolicy();

  /// Never purged automatically (until the next OS update).
  static const CachePolicy persistent = CachePolicy(
    purgeOnStoragePressure: false,
    purgeOnSourceAssetChangedOrDeleted: false,
  );

  /// Whether the system may purge the entry when storage runs low.
  final bool purgeOnStoragePressure;

  /// Whether the system may purge the entry when its `.aimodel` changes or
  /// is deleted.
  final bool purgeOnSourceAssetChangedOrDeleted;

  /// The Pigeon representation.
  CachePolicyMessage toMessage() => CachePolicyMessage(
    purgeOnStoragePressure: purgeOnStoragePressure,
    purgeOnSourceAssetChangedOrDeleted: purgeOnSourceAssetChangedOrDeleted,
  );

  @override
  bool operator ==(Object other) =>
      other is CachePolicy &&
      other.purgeOnStoragePressure == purgeOnStoragePressure &&
      other.purgeOnSourceAssetChangedOrDeleted ==
          purgeOnSourceAssetChangedOrDeleted;

  @override
  int get hashCode =>
      Object.hash(purgeOnStoragePressure, purgeOnSourceAssetChangedOrDeleted);
}

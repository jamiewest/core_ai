import 'bindings.dart';
import 'errors.dart';
import 'modules.dart';

/// Model installation state from `AssetInventory`.
enum AssetStatus {
  /// The modules are unsupported.
  unsupported,

  /// Assets are supported but not reported installed.
  supported,

  /// Assets are downloading.
  downloading,

  /// All requested assets are installed.
  installed,
}

/// Model assets and locale reservations for `SpeechAnalyzer` (iOS/macOS 26).
abstract final class AssetInventory {
  /// Reports the status of the requested modules. Dictation may report
  /// [AssetStatus.supported] even when its locale is installed.
  static Future<AssetStatus> status(List<SpeechModule> modules) async =>
      AssetStatus.values[(await guardPlatformCall(
        () => SpeechBindings.instance.host.assetStatus(
          modules.map((m) => m.toMessage()).toList(),
        ),
      )).index];

  /// Downloads missing models, reporting progress from 0 to 1. Returns false
  /// when no download is needed. Call only following an explicit user action.
  /// [Speech.cancelAll] also cancels active installations.
  static Future<bool> installAssets(
    List<SpeechModule> modules, {
    void Function(double fractionCompleted)? onProgress,
  }) async {
    final bindings = SpeechBindings.instance;
    final id = bindings.nextRequestId();
    bindings.registerRequest(id, _InstallProgress(onProgress));
    try {
      return await guardPlatformCall(
        () => bindings.host.installAssets(
          id,
          modules.map((m) => m.toMessage()).toList(),
        ),
      );
    } finally {
      bindings.unregisterRequest(id);
    }
  }

  /// Locales this app has reserved to keep their models installed.
  static Future<List<String>> reservedLocales() =>
      guardPlatformCall(() => SpeechBindings.instance.host.reservedLocales());

  /// Maximum number of locale reservations allowed by Apple.
  static Future<int> maximumReservedLocales() => guardPlatformCall(
    () => SpeechBindings.instance.host.maximumReservedLocales(),
  );

  /// Reserves [locale]; returns false if already reserved.
  static Future<bool> reserve(String locale) => guardPlatformCall(
    () => SpeechBindings.instance.host.reserveLocale(locale),
  );

  /// Releases this app's reservation, returning whether one was removed.
  static Future<bool> release(String locale) => guardPlatformCall(
    () => SpeechBindings.instance.host.releaseLocale(locale),
  );
}

final class _InstallProgress extends RequestSink {
  _InstallProgress(this.onProgress);
  final void Function(double)? onProgress;
  @override
  void onInstallProgress(double fractionCompleted) =>
      onProgress?.call(fractionCompleted);
}

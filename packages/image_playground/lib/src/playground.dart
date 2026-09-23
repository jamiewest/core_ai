import 'package:flutter/services.dart';
import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'types.dart';

/// Apple's system Image Playground sheet.
///
/// Images are created in Apple's interface. The programmatic `ImageCreator`
/// API is not bridged: it is deprecated in iOS 27 / macOS 27, and on macOS 27
/// it throws `notSupported` even where the sheet is available.
abstract final class ImagePlayground {
  /// Whether the framework exists on this OS (not model readiness).
  static Future<bool> isSupported() async {
    try {
      return await ImagePlaygroundBindings.instance.platform.isSupported();
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      if (error.code == 'channel-error') return false;
      throw ImagePlaygroundException.fromPlatformException(error);
    }
  }

  /// Current framework/device support and option availability.
  static Future<ImagePlaygroundCapabilities> capabilities() async {
    try {
      return ImagePlaygroundCapabilities.fromMessage(
        await guardPlatformCall(
          () => ImagePlaygroundBindings.instance.platform.capabilities(),
        ),
      );
    } on ImagePlaygroundException catch (error) {
      if (error.code != ImagePlaygroundErrorCode.unsupported) rethrow;
      return ImagePlaygroundCapabilities.fromMessage(
        CapabilitiesMessage(
          isSupported: false,
          isAvailable: false,
          supportsStyles: false,
          supportsOptions: false,
          supportsVersion27Options: false,
          styles: [],
        ),
      );
    }
  }

  /// Prepares a one-use system sheet. This validates and decodes inputs but
  /// does not show UI or generate images. Dispose the returned session.
  static Future<ImagePlaygroundSession> prepare({
    List<ImagePlaygroundConcept> concepts = const [],
    ImageInput? sourceImage,
    List<ImagePlaygroundStyle>? allowedStyles,
    ImagePlaygroundStyle? selectedStyle,
    ImagePlaygroundOptions? options,
  }) async {
    final bindings = ImagePlaygroundBindings.instance;
    final message = ConfigurationMessage(
      concepts: concepts.map((c) => c.toMessage()).toList(),
      sourceImage: sourceImage?.toMessage(),
      allowedStyles: allowedStyles
          ?.map((s) => StyleMessage.values[s.index])
          .toList(),
      selectedStyle: selectedStyle == null
          ? null
          : StyleMessage.values[selectedStyle.index],
      options: options?.toMessage(),
    );
    final handle = await guardPlatformCall(
      () => bindings.host.prepare(message),
    );
    return ImagePlaygroundSession._(bindings, handle);
  }

  /// Convenience for preparing, presenting and disposing a sheet. Returns
  /// null on cancellation. Use [prepare] to cancel from your own controls.
  static Future<ImagePlaygroundResult?> present({
    List<ImagePlaygroundConcept> concepts = const [],
    ImageInput? sourceImage,
    List<ImagePlaygroundStyle>? allowedStyles,
    ImagePlaygroundStyle? selectedStyle,
    ImagePlaygroundOptions? options,
  }) async {
    final session = await prepare(
      concepts: concepts,
      sourceImage: sourceImage,
      allowedStyles: allowedStyles,
      selectedStyle: selectedStyle,
      options: options,
    );
    try {
      return await session.present();
    } finally {
      await session.dispose();
    }
  }

  /// Releases every native session and cancels any open sheet. Existing Dart
  /// wrappers become invalid; dispose them before using this global cleanup.
  static Future<int> releaseAll() => guardPlatformCall(
    () => ImagePlaygroundBindings.instance.host.releaseAll(),
  );

  /// Native handles still owned by this Flutter engine.
  static Future<int> liveHandleCount() => guardPlatformCall(
    () => ImagePlaygroundBindings.instance.host.liveHandleCount(),
  );
}

/// Owns a single native sheet. The session can be presented once; cancel and
/// dispose it when its Flutter screen is removed.
final class ImagePlaygroundSession {
  ImagePlaygroundSession._(this._bindings, this._handle) {
    _bindings.finalizer.attach(this, _handle, detach: this);
  }
  final ImagePlaygroundBindings _bindings;
  final int _handle;
  bool _disposed = false;
  bool _presented = false;
  bool _cancelled = false;
  Future<void>? _disposal;
  Future<void>? _cancellation;

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  /// Native handle, exposed for diagnostics. Throws after disposal.
  int get handle {
    if (_disposed) throw StateError('Image Playground session was disposed.');
    return _handle;
  }

  /// Shows the sheet and waits for user completion. Null means cancellation.
  /// Concurrent sheets on the same Flutter controller produce a busy error.
  Future<ImagePlaygroundResult?> present() async {
    final id = handle;
    if (_presented || _cancelled) {
      throw StateError('Each session can be presented once.');
    }
    _presented = true;
    final result = await guardPlatformCall(() => _bindings.host.present(id));
    return result == null ? null : ImagePlaygroundResult.fromMessage(result);
  }

  /// Reads the native controller configuration and presentation state.
  Future<ImagePlaygroundSessionInfo> info() async {
    final id = handle;
    return ImagePlaygroundSessionInfo.fromMessage(
      await guardPlatformCall(() => _bindings.host.info(id)),
    );
  }

  /// Closes the sheet and resolves [present] with null. Also prevents a
  /// prepared session from opening later. Safe to repeat, including disposed.
  Future<void> cancel() {
    if (_disposed) return _disposal ?? Future.value();
    _cancelled = true;
    return _cancellation ??= guardPlatformCall(
      () => _bindings.host.cancel(_handle),
    );
  }

  /// Releases native ownership, cancelling an open sheet. Safe to repeat.
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _bindings.finalizer.detach(this);
    await guardPlatformCall(() => _bindings.host.release(_handle));
  }
}

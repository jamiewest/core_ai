import 'bindings.dart';
import 'errors.dart';

/// A Dart object that owns a native object through an opaque handle.
///
/// Call [dispose] when done. If an object is garbage collected without being
/// disposed, its native object is released later by a [Finalizer].
abstract base class NativeResource {
  /// Takes ownership of [handle].
  NativeResource(this._handle) : bindings = FoundationModelsBindings.instance {
    bindings.finalizer.attach(this, _handle, detach: this);
  }

  final int _handle;

  /// The bindings this object was created with.
  final FoundationModelsBindings bindings;

  bool _disposed = false;

  /// The opaque native handle.
  ///
  /// Throws a [StateError] after [dispose].
  int get handle {
    if (_disposed) {
      throw StateError('$runtimeType was used after being disposed.');
    }
    return _handle;
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Called before the native object is released.
  void onDispose() {}

  /// Releases the native object. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    onDispose();
    _disposed = true;
    bindings.finalizer.detach(this);
    await guardPlatformCall(() => bindings.host.release(_handle));
  }
}

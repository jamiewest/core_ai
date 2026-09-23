import 'bindings.dart';
import 'errors.dart';

/// A Dart object that owns a native Core AI object through an opaque handle.
///
/// Call [dispose] when done. If an object is garbage collected without being
/// disposed, its native object is released automatically, but only at some
/// unspecified later time, so prefer disposing explicitly.
abstract base class NativeResource {
  /// Takes ownership of [handle].
  NativeResource(this._handle) : bindings = CoreAIBindings.instance {
    bindings.finalizer.attach(this, _handle, detach: this);
  }

  final int _handle;

  /// The bindings this object was created with.
  final CoreAIBindings bindings;

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

  /// Releases the native object. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    bindings.finalizer.detach(this);
    await guardPlatformCall(() => bindings.host.release(_handle));
  }
}

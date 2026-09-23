part of 'values.dart';

/// What a [NativeValue] currently holds.
enum NativeValueKind {
  /// An NDArray.
  ndArray,

  /// A pixel buffer.
  image,

  /// The pending result of `InferenceFunction.encode`, which completes when
  /// its compute stream finishes the work that produces it.
  asyncValue,

  /// A state or output view updated by encoded work that may still be
  /// running.
  asyncMutableValue,
}

/// Image encodings for [NativeValue.encodeImage].
enum ImageEncoding {
  /// Lossless PNG.
  png,

  /// Lossy JPEG.
  jpeg,
}

/// Layout information about a [NativeValue], without its contents.
@immutable
final class NativeValueInfo {
  /// Creates an info object.
  const NativeValueInfo({
    required this.kind,
    this.scalarType,
    this.shape,
    this.strides,
    this.interleaveLayout,
    this.byteCount,
    this.width,
    this.height,
    this.pixelFormatType,
  });

  factory NativeValueInfo._fromMessage(NativeValueInfoMessage message) {
    final interleave = message.interleaveLayout;
    return NativeValueInfo(
      kind: NativeValueKind.values[message.kind.index],
      scalarType: message.scalarType?.toScalarType(),
      shape: message.shape,
      strides: message.strides,
      interleaveLayout: interleave == null
          ? null
          : InterleaveLayout.fromMessage(interleave),
      byteCount: message.byteCount,
      width: message.width,
      height: message.height,
      pixelFormatType: message.pixelFormatType,
    );
  }

  /// What the value holds. Async kinds report no layout until resolved.
  final NativeValueKind kind;

  /// The NDArray element type.
  final ScalarType? scalarType;

  /// The NDArray shape.
  final List<int>? shape;

  /// The NDArray element strides.
  final List<int>? strides;

  /// The NDArray interleave layout.
  final InterleaveLayout? interleaveLayout;

  /// The size of the backing storage in bytes.
  final int? byteCount;

  /// The pixel buffer width.
  final int? width;

  /// The pixel buffer height.
  final int? height;

  /// The pixel buffer format.
  final int? pixelFormatType;

  @override
  String toString() => switch (kind) {
    NativeValueKind.ndArray => 'NativeValueInfo(${scalarType?.name} $shape)',
    NativeValueKind.image =>
      'NativeValueInfo(${width}x$height '
          '${PixelFormat.describe(pixelFormatType ?? 0)})',
    _ => 'NativeValueInfo(${kind.name})',
  };
}

/// An NDArray or pixel buffer that lives on the native side.
///
/// Native values avoid copying data across the platform channel. Use them to:
///
/// * hold function state (such as a key-value cache) across calls, see
///   `InferenceFunction.makeState`;
/// * keep outputs native and feed them to another function, see the
///   `retain` argument of `InferenceFunction.run`;
/// * pre-allocate outputs (`outputViews`) that are updated in place;
/// * pipeline work on a `ComputeStream`, whose outputs are async values.
///
/// A value can be read by several operations at once but written by only one;
/// conflicting use fails with [CoreAIErrorCode.busy].
final class NativeValue extends NativeResource implements InferenceValue {
  NativeValue._(super.handle);

  /// Copies [array] to a new native value.
  static Future<NativeValue> fromNDArray(NDArray array) async {
    final host = CoreAIBindings.instance.host;
    final handle = await guardPlatformCall(
      () => host.createNDArray(array.toMessage()),
    );
    return NativeValue._(handle);
  }

  /// Copies [buffer] to a new native pixel buffer.
  static Future<NativeValue> fromPixelBuffer(PixelBuffer buffer) async {
    final host = CoreAIBindings.instance.host;
    final handle = await guardPlatformCall(
      () => host.createPixelBuffer(buffer.toMessage()),
    );
    return NativeValue._(handle);
  }

  /// Decodes an encoded image (PNG, JPEG, HEIC, ...) on the native side,
  /// resizes it to [width] x [height] (keeping its size when omitted) and
  /// converts it to [pixelFormatType].
  ///
  /// Pixel values are copied without color management, the way most image
  /// models expect. Pass an [ImageDescriptor]'s size and format to match a
  /// model input directly.
  static Future<NativeValue> fromEncodedImage(
    Uint8List encoded, {
    int pixelFormatType = PixelFormat.bgra32,
    int? width,
    int? height,
  }) async {
    final host = CoreAIBindings.instance.host;
    final handle = await guardPlatformCall(
      () => host.createPixelBufferFromEncodedImage(
        encoded,
        pixelFormatType,
        width,
        height,
      ),
    );
    return NativeValue._(handle);
  }

  /// Allocates a zero-filled native NDArray.
  static Future<NativeValue> zeros(
    ScalarType scalarType,
    List<int> shape, {
    List<int>? strides,
    InterleaveLayout? interleaveLayout,
  }) async {
    final host = CoreAIBindings.instance.host;
    final handle = await guardPlatformCall(
      () => host.allocateNDArray(
        scalarType.toMessage(),
        shape,
        strides,
        interleaveLayout?.toMessage(),
      ),
    );
    return NativeValue._(handle);
  }

  /// Copies the contents to Dart: an [NDArray] or a [PixelBuffer].
  ///
  /// Async values are awaited first.
  Future<InferenceValue> read() async {
    final message = await guardPlatformCall(
      () => bindings.host.readValue(handle),
    );
    return valueFromMessage(message);
  }

  /// Copies the contents to Dart as an [NDArray].
  Future<NDArray> readNDArray() async => switch (await read()) {
    final NDArray array => array,
    _ => throw const CoreAIException(
      CoreAIErrorCode.invalidArgument,
      'This native value is not an NDArray.',
    ),
  };

  /// Copies the contents to Dart as a [PixelBuffer].
  Future<PixelBuffer> readPixelBuffer() async => switch (await read()) {
    final PixelBuffer buffer => buffer,
    _ => throw const CoreAIException(
      CoreAIErrorCode.invalidArgument,
      'This native value is not a pixel buffer.',
    ),
  };

  /// Encodes a pixel-buffer value as an image file, for example to show with
  /// `Image.memory`. [quality] (0 to 1) applies to JPEG.
  Future<Uint8List> encodeImage({
    ImageEncoding encoding = ImageEncoding.png,
    double quality = 0.9,
  }) => guardPlatformCall(
    () => bindings.host.encodePixelBuffer(
      handle,
      ImageEncodingMessage.values[encoding.index],
      quality,
    ),
  );

  /// Overwrites an NDArray value with [array], which must have the same
  /// scalar type, shape, strides and interleave layout.
  Future<void> write(NDArray array) => guardPlatformCall(
    () => bindings.host.writeNDArray(handle, array.toMessage()),
  );

  /// Fills the value with zeros.
  Future<void> zero() =>
      guardPlatformCall(() => bindings.host.zeroValue(handle));

  /// An independent native copy.
  Future<NativeValue> copy() async {
    final copied = await guardPlatformCall(
      () => bindings.host.copyValue(handle),
    );
    return NativeValue._(copied);
  }

  /// Layout information, without copying the contents.
  Future<NativeValueInfo> describe() async {
    final info = await guardPlatformCall(
      () => bindings.host.describeValue(handle),
    );
    return NativeValueInfo._fromMessage(info);
  }

  @override
  String toString() => 'NativeValue(${isDisposed ? 'disposed' : handle})';
}

/// Wraps a native value handle returned by the host API.
NativeValue adoptNativeValue(int handle) => NativeValue._(handle);

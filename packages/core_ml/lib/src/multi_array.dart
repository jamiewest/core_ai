part of 'values.dart';

/// A multidimensional array of scalars (Core ML's `MLMultiArray`), held in
/// Dart memory.
///
/// The data is kept as raw little-endian storage in [bytes] with an explicit
/// [shape] and element [strides], so Core ML's non-contiguous arrays survive
/// the trip across the platform channel: a float16 output backed by a
/// `CVPixelBuffer` has its rows padded for alignment, which shows up as a
/// stride larger than the row length.
///
/// ```dart
/// final x = MLMultiArray.float32([1, 2, 3]);
/// final prediction = await model.predict({'x': x});
/// print(prediction.multiArray('y').toDoubleList());
/// ```
@immutable
final class MLMultiArray extends MLFeatureValue {
  const MLMultiArray._(this.dataType, this.shape, this.strides, this.bytes);

  /// Wraps existing raw storage.
  ///
  /// [strides] are in elements and default to row-major contiguous. The size
  /// of [bytes] must cover the layout exactly.
  factory MLMultiArray.fromBytes(
    Uint8List bytes, {
    required MLMultiArrayDataType dataType,
    required List<int> shape,
    List<int>? strides,
  }) {
    _checkShape(shape);
    final layout = strides ?? contiguousStrides(shape);
    if (layout.length != shape.length) {
      throw ArgumentError.value(
        strides,
        'strides',
        'must have the same rank as shape $shape',
      );
    }
    final required = storageElements(shape, layout) * dataType.byteCount;
    if (bytes.length != required) {
      throw ArgumentError(
        'A ${dataType.name} array with shape $shape and strides $layout needs '
        '$required bytes of storage, got ${bytes.length}.',
      );
    }
    return MLMultiArray._(
      dataType,
      List.unmodifiable(shape),
      List.unmodifiable(layout),
      bytes,
    );
  }

  /// A contiguous array of [values], converted to [dataType].
  factory MLMultiArray.fromList(
    List<num> values, {
    required MLMultiArrayDataType dataType,
    List<int>? shape,
  }) {
    final dims = shape ?? [values.length];
    _checkShape(dims);
    if (_product(dims) != values.length) {
      throw ArgumentError(
        '${values.length} values do not fill shape $dims '
        '(${_product(dims)} elements).',
      );
    }
    final codec = _ElementCodec.of(dataType);
    final bytes = Uint8List(values.length * codec.size);
    final data = ByteData.sublistView(bytes);
    for (var index = 0; index < values.length; index++) {
      codec.write(data, index * codec.size, values[index]);
    }
    return MLMultiArray._(
      dataType,
      List.unmodifiable(dims),
      List.unmodifiable(contiguousStrides(dims)),
      bytes,
    );
  }

  /// A float16 array.
  factory MLMultiArray.float16(List<num> values, {List<int>? shape}) =>
      MLMultiArray.fromList(
        values,
        dataType: MLMultiArrayDataType.float16,
        shape: shape,
      );

  /// A float32 array.
  factory MLMultiArray.float32(List<num> values, {List<int>? shape}) =>
      MLMultiArray.fromList(
        values,
        dataType: MLMultiArrayDataType.float32,
        shape: shape,
      );

  /// A float64 array (`MLMultiArrayDataTypeDouble`).
  factory MLMultiArray.float64(List<num> values, {List<int>? shape}) =>
      MLMultiArray.fromList(
        values,
        dataType: MLMultiArrayDataType.float64,
        shape: shape,
      );

  /// An int32 array.
  factory MLMultiArray.int32(List<int> values, {List<int>? shape}) =>
      MLMultiArray.fromList(
        values,
        dataType: MLMultiArrayDataType.int32,
        shape: shape,
      );

  /// An int8 array. Core ML needs iOS 26 / macOS 26 for these.
  factory MLMultiArray.int8(List<int> values, {List<int>? shape}) =>
      MLMultiArray.fromList(
        values,
        dataType: MLMultiArrayDataType.int8,
        shape: shape,
      );

  /// Converts from the Pigeon representation.
  factory MLMultiArray.fromMessage(MultiArrayMessage message) => MLMultiArray._(
    MLMultiArrayDataType.fromMessage(message.dataType),
    List.unmodifiable(message.shape),
    List.unmodifiable(
      message.strides.isEmpty
          ? contiguousStrides(message.shape)
          : message.strides,
    ),
    message.data,
  );

  /// The element type.
  final MLMultiArrayDataType dataType;

  /// The length of each dimension.
  final List<int> shape;

  /// The distance, in elements, between consecutive values along each
  /// dimension.
  final List<int> strides;

  /// The raw storage (little-endian).
  final Uint8List bytes;

  /// The number of dimensions.
  int get rank => shape.length;

  /// The number of logical elements (Core ML's `count`).
  int get count => _product(shape);

  /// Whether the storage is row-major contiguous, so element `i` of
  /// [toDoubleList] is element `i` of the storage.
  bool get isContiguous => listEquals(strides, contiguousStrides(shape));

  /// The element at [index] (one entry per dimension), as a Dart number.
  num elementAt(List<int> index) {
    if (index.length != rank) {
      throw RangeError('Index $index does not match rank $rank.');
    }
    for (var d = 0; d < rank; d++) {
      RangeError.checkValueInInterval(index[d], 0, shape[d] - 1, 'index[$d]');
    }
    final codec = _ElementCodec.of(dataType);
    return codec.read(
      ByteData.sublistView(bytes),
      _elementOffset(index) * codec.size,
    );
  }

  /// All elements in logical row-major order, as doubles.
  List<double> toDoubleList() =>
      _decode().map((value) => value.toDouble()).toList(growable: false);

  /// All elements in logical row-major order, as integers.
  ///
  /// Floating-point values are truncated.
  List<int> toIntList() =>
      _decode().map((value) => value.toInt()).toList(growable: false);

  /// All elements in logical row-major order, converted to float32.
  Float32List toFloat32List() {
    final view = asFloat32List();
    if (view != null) return Float32List.fromList(view);
    return Float32List.fromList(toDoubleList());
  }

  /// A zero-copy float32 view of [bytes], when the array is contiguous
  /// float32 and suitably aligned; otherwise null.
  Float32List? asFloat32List() {
    if (dataType != MLMultiArrayDataType.float32 || !isContiguous) return null;
    if ((bytes.offsetInBytes % 4) != 0) return null;
    return bytes.buffer.asFloat32List(bytes.offsetInBytes, count);
  }

  /// The same contiguous data viewed with a different [newShape].
  MLMultiArray reshaped(List<int> newShape) {
    _checkShape(newShape);
    if (!isContiguous) {
      throw StateError('Only contiguous arrays can be reshaped.');
    }
    if (_product(newShape) != count) {
      throw ArgumentError('Cannot reshape $shape to $newShape.');
    }
    return MLMultiArray._(
      dataType,
      List.unmodifiable(newShape),
      List.unmodifiable(contiguousStrides(newShape)),
      bytes,
    );
  }

  @override
  MultiArrayMessage toMessage() => MultiArrayMessage(
    dataType: dataType.toMessage(),
    shape: shape,
    strides: strides,
    data: bytes,
  );

  List<num> _decode() {
    final codec = _ElementCodec.of(dataType);
    final data = ByteData.sublistView(bytes);
    final total = count;
    final result = List<num>.filled(total, 0);
    if (isContiguous) {
      for (var i = 0; i < total; i++) {
        result[i] = codec.read(data, i * codec.size);
      }
      return result;
    }
    final index = List<int>.filled(rank, 0);
    for (var i = 0; i < total; i++) {
      result[i] = codec.read(data, _elementOffset(index) * codec.size);
      for (var d = rank - 1; d >= 0; d--) {
        if (++index[d] < shape[d]) break;
        index[d] = 0;
      }
    }
    return result;
  }

  int _elementOffset(List<int> index) {
    var offset = 0;
    for (var d = 0; d < rank; d++) {
      offset += index[d] * strides[d];
    }
    return offset;
  }

  @override
  String toString() => 'MLMultiArray(${dataType.name}, $shape)';
}

/// Row-major contiguous element strides for [shape].
List<int> contiguousStrides(List<int> shape) {
  final strides = List<int>.filled(shape.length, 1);
  var stride = 1;
  for (var d = shape.length - 1; d >= 0; d--) {
    strides[d] = stride;
    stride *= math.max(shape[d], 1);
  }
  return strides;
}

/// The number of elements a strided layout spans (largest offset plus one).
int storageElements(List<int> shape, List<int> strides) {
  if (shape.contains(0)) return 0;
  var maxOffset = 0;
  for (var d = 0; d < shape.length; d++) {
    maxOffset += (shape[d] - 1) * strides[d];
  }
  return maxOffset + 1;
}

int _product(List<int> shape) => shape.fold(1, (a, b) => a * b);

void _checkShape(List<int> shape) {
  if (shape.any((d) => d < 0)) {
    throw ArgumentError.value(
      shape,
      'shape',
      'must not contain negative sizes',
    );
  }
}

/// Reads and writes single elements of an [MLMultiArrayDataType].
final class _ElementCodec {
  const _ElementCodec(this.size, this.read, this.write);

  factory _ElementCodec.of(MLMultiArrayDataType type) => switch (type) {
    MLMultiArrayDataType.int8 => _ElementCodec(
      1,
      (d, o) => d.getInt8(o),
      (d, o, v) => d.setInt8(o, v.toInt()),
    ),
    MLMultiArrayDataType.int32 => _ElementCodec(
      4,
      (d, o) => d.getInt32(o, Endian.little),
      (d, o, v) => d.setInt32(o, v.toInt(), Endian.little),
    ),
    MLMultiArrayDataType.float16 => _ElementCodec(
      2,
      (d, o) => halfBitsToDouble(d.getUint16(o, Endian.little)),
      (d, o, v) =>
          d.setUint16(o, doubleToHalfBits(v.toDouble()), Endian.little),
    ),
    MLMultiArrayDataType.float32 => _ElementCodec(
      4,
      (d, o) => d.getFloat32(o, Endian.little),
      (d, o, v) => d.setFloat32(o, v.toDouble(), Endian.little),
    ),
    MLMultiArrayDataType.float64 => _ElementCodec(
      8,
      (d, o) => d.getFloat64(o, Endian.little),
      (d, o, v) => d.setFloat64(o, v.toDouble(), Endian.little),
    ),
  };

  final int size;
  final num Function(ByteData data, int offset) read;
  final void Function(ByteData data, int offset, num value) write;
}

/// Decodes IEEE 754 half-precision bits.
double halfBitsToDouble(int bits) {
  final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
  final exponent = (bits >> 10) & 0x1F;
  final mantissa = bits & 0x3FF;
  if (exponent == 0) return sign * mantissa * math.pow(2, -24);
  if (exponent == 0x1F) {
    return mantissa == 0 ? sign * double.infinity : double.nan;
  }
  return sign * (1 + mantissa / 1024) * math.pow(2, exponent - 15);
}

/// Encodes [value] as IEEE 754 half-precision bits, rounding to nearest even.
int doubleToHalfBits(double value) {
  final bits = _float32Bits(value);
  final sign = (bits >> 16) & 0x8000;
  if ((bits & 0x7FFFFFFF) > 0x7F800000) return sign | 0x7E00;
  final exponent = ((bits >> 23) & 0xFF) - 127 + 15;
  var mantissa = bits & 0x7FFFFF;
  if (exponent >= 0x1F) return sign | 0x7C00;
  if (exponent <= 0) {
    if (exponent < -10) return sign;
    mantissa |= 0x800000;
    final shift = 14 - exponent;
    var half = mantissa >> shift;
    final remainder = mantissa & ((1 << shift) - 1);
    final halfway = 1 << (shift - 1);
    if (remainder > halfway || (remainder == halfway && (half & 1) == 1)) {
      half++;
    }
    return sign | half;
  }
  var half = (exponent << 10) | (mantissa >> 13);
  final remainder = mantissa & 0x1FFF;
  if (remainder > 0x1000 || (remainder == 0x1000 && (half & 1) == 1)) {
    half++;
  }
  return sign | half;
}

int _float32Bits(double value) =>
    (ByteData(4)..setFloat32(0, value)).getUint32(0);

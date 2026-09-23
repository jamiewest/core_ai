part of 'values.dart';

/// A multidimensional array of scalars (Core AI's `NDArray`), held in Dart
/// memory.
///
/// The data is kept as raw little-endian storage in [bytes] with an explicit
/// [shape], element [strides] and optional [interleaveLayout], so every Core
/// AI scalar type, including packed sub-byte and 8-bit float types, passes
/// through unchanged. Typed constructors and accessors cover the types with a
/// Dart representation (see [ScalarType.hasDartRepresentation]).
///
/// ```dart
/// final x = NDArray.float32([1, 2, 3, 4], shape: [2, 2]);
/// final outputs = await function.run({'x': x});
/// print(outputs.ndArray('y').toDoubleList());
/// ```
@immutable
final class NDArray implements InferenceValue {
  NDArray._(
    this.scalarType,
    List<int> shape,
    List<int> strides,
    this.interleaveLayout,
    this.bytes,
  ) : shape = List.unmodifiable(shape),
      strides = List.unmodifiable(strides);

  /// Wraps existing raw storage.
  ///
  /// [strides] are in elements and default to row-major contiguous. The size
  /// of [bytes] is checked for byte-aligned types; for sub-byte types it must
  /// match Core AI's packing, which the native side verifies.
  factory NDArray.fromBytes(
    Uint8List bytes, {
    required ScalarType scalarType,
    required List<int> shape,
    List<int>? strides,
    InterleaveLayout? interleaveLayout,
  }) {
    _checkShape(shape);
    final layoutStrides = strides ?? contiguousStrides(shape);
    if (layoutStrides.length != shape.length) {
      throw ArgumentError.value(
        strides,
        'strides',
        'must have the same rank as shape $shape',
      );
    }
    if (interleaveLayout != null && strides == null) {
      throw ArgumentError('An interleave layout requires explicit strides.');
    }
    if (scalarType.isByteAligned) {
      final required =
          _storageElements(shape, layoutStrides, interleaveLayout) *
          (scalarType.bitWidth ~/ 8);
      if (bytes.length < required) {
        throw ArgumentError.value(
          bytes.length,
          'bytes.length',
          '${scalarType.name} $shape with strides $layoutStrides needs '
              'at least $required bytes',
        );
      }
    }
    return NDArray._(scalarType, shape, layoutStrides, interleaveLayout, bytes);
  }

  /// A zero-filled, contiguous array.
  factory NDArray.zeros(ScalarType scalarType, List<int> shape) {
    _checkShape(shape);
    return NDArray._(
      scalarType,
      shape,
      contiguousStrides(shape),
      null,
      Uint8List(scalarType.byteCountFor(_product(shape))),
    );
  }

  /// Encodes [values] (in row-major order) as [scalarType].
  ///
  /// Throws an [UnsupportedError] for types without a Dart representation.
  factory NDArray.fromList(
    List<num> values, {
    required ScalarType scalarType,
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
    final codec = _ElementCodec.of(scalarType);
    final bytes = Uint8List(values.length * codec.size);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < values.length; i++) {
      codec.write(data, i * codec.size, values[i]);
    }
    return NDArray._(scalarType, dims, contiguousStrides(dims), null, bytes);
  }

  /// A float32 array. [shape] defaults to one dimension.
  factory NDArray.float32(List<double> values, {List<int>? shape}) =>
      _typed(ScalarType.float32, values, shape);

  /// A float64 array.
  factory NDArray.float64(List<double> values, {List<int>? shape}) =>
      _typed(ScalarType.float64, values, shape);

  /// A float16 array, rounding each value to the nearest half.
  factory NDArray.float16(List<double> values, {List<int>? shape}) =>
      NDArray.fromList(values, scalarType: ScalarType.float16, shape: shape);

  /// A bfloat16 array, rounding each value to the nearest bfloat16.
  factory NDArray.bfloat16(List<double> values, {List<int>? shape}) =>
      NDArray.fromList(values, scalarType: ScalarType.bfloat16, shape: shape);

  /// An int8 array.
  factory NDArray.int8(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.int8, values, shape);

  /// An int16 array.
  factory NDArray.int16(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.int16, values, shape);

  /// An int32 array.
  factory NDArray.int32(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.int32, values, shape);

  /// An int64 array.
  factory NDArray.int64(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.int64, values, shape);

  /// A uint8 array.
  factory NDArray.uint8(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.uint8, values, shape);

  /// A uint16 array.
  factory NDArray.uint16(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.uint16, values, shape);

  /// A uint32 array.
  factory NDArray.uint32(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.uint32, values, shape);

  /// A uint64 array.
  factory NDArray.uint64(List<int> values, {List<int>? shape}) =>
      _typed(ScalarType.uint64, values, shape);

  /// A Boolean array (one byte per element).
  factory NDArray.boolean(List<bool> values, {List<int>? shape}) =>
      NDArray.fromList(
        [for (final value in values) value ? 1 : 0],
        scalarType: ScalarType.boolean,
        shape: shape,
      );

  /// Converts from the Pigeon representation.
  factory NDArray.fromMessage(NDArrayMessage message) {
    final interleave = message.interleaveLayout;
    return NDArray._(
      message.scalarType.toScalarType(),
      message.shape,
      message.strides.isEmpty
          ? contiguousStrides(message.shape)
          : message.strides,
      interleave == null ? null : InterleaveLayout.fromMessage(interleave),
      message.data,
    );
  }

  static NDArray _typed(ScalarType type, List<num> values, List<int>? shape) {
    final dims = shape ?? [values.length];
    _checkShape(dims);
    if (_product(dims) != values.length) {
      throw ArgumentError(
        '${values.length} values do not fill shape $dims '
        '(${_product(dims)} elements).',
      );
    }
    final TypedData data = switch (type) {
      ScalarType.float32 => Float32List.fromList(values.cast<double>()),
      ScalarType.float64 => Float64List.fromList(values.cast<double>()),
      ScalarType.int8 => Int8List.fromList(values.cast<int>()),
      ScalarType.int16 => Int16List.fromList(values.cast<int>()),
      ScalarType.int32 => Int32List.fromList(values.cast<int>()),
      ScalarType.int64 => Int64List.fromList(values.cast<int>()),
      ScalarType.uint8 => Uint8List.fromList(values.cast<int>()),
      ScalarType.uint16 => Uint16List.fromList(values.cast<int>()),
      ScalarType.uint32 => Uint32List.fromList(values.cast<int>()),
      ScalarType.uint64 => Uint64List.fromList(values.cast<int>()),
      _ => throw StateError('No typed list for $type.'),
    };
    return NDArray._(
      type,
      dims,
      contiguousStrides(dims),
      null,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  /// The element type.
  final ScalarType scalarType;

  /// The length of each dimension.
  final List<int> shape;

  /// The distance, in elements, between consecutive values along each
  /// dimension. For an interleaved dimension this is a block stride.
  final List<int> strides;

  /// The interleaved layout, if any.
  final InterleaveLayout? interleaveLayout;

  /// The raw storage (little-endian).
  final Uint8List bytes;

  /// The number of dimensions.
  int get rank => shape.length;

  /// The number of logical elements.
  int get elementCount => _product(shape);

  /// Whether the storage is row-major contiguous with no interleave, so
  /// element `i` of [toDoubleList] is element `i` of the storage.
  bool get isContiguous =>
      interleaveLayout == null && listEquals(strides, contiguousStrides(shape));

  /// The element at [index] (one entry per dimension), as a Dart number.
  num elementAt(List<int> index) {
    if (index.length != rank) {
      throw RangeError('Index $index does not match rank $rank.');
    }
    for (var d = 0; d < rank; d++) {
      RangeError.checkValueInInterval(index[d], 0, shape[d] - 1, 'index[$d]');
    }
    final codec = _ElementCodec.of(scalarType);
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
  /// Floating-point values are truncated. uint64 values above 2^63 - 1 wrap
  /// to negative Dart integers.
  List<int> toIntList() =>
      _decode().map((value) => value.toInt()).toList(growable: false);

  /// All elements in logical row-major order, as Booleans (non-zero is true).
  List<bool> toBoolList() =>
      _decode().map((value) => value != 0).toList(growable: false);

  /// All elements in logical row-major order, converted to float32.
  Float32List toFloat32List() {
    final view = asFloat32List();
    if (view != null) return Float32List.fromList(view);
    return Float32List.fromList(toDoubleList());
  }

  /// A zero-copy float32 view of [bytes], when the array is contiguous
  /// float32 and suitably aligned; otherwise null.
  Float32List? asFloat32List() {
    if (scalarType != ScalarType.float32 || !isContiguous) return null;
    if ((bytes.offsetInBytes % 4) != 0) return null;
    return bytes.buffer.asFloat32List(bytes.offsetInBytes, elementCount);
  }

  /// The same contiguous data viewed with a different [newShape].
  NDArray reshaped(List<int> newShape) {
    _checkShape(newShape);
    if (!isContiguous) {
      throw StateError('Only contiguous arrays can be reshaped.');
    }
    if (_product(newShape) != elementCount) {
      throw ArgumentError('Cannot reshape $shape to $newShape.');
    }
    return NDArray._(
      scalarType,
      newShape,
      contiguousStrides(newShape),
      null,
      bytes,
    );
  }

  /// The Pigeon representation.
  NDArrayMessage toMessage() => NDArrayMessage(
    scalarType: scalarType.toMessage(),
    shape: shape,
    strides: strides,
    interleaveLayout: interleaveLayout?.toMessage(),
    data: bytes,
  );

  List<num> _decode() {
    final codec = _ElementCodec.of(scalarType);
    final data = ByteData.sublistView(bytes);
    final count = elementCount;
    final result = List<num>.filled(count, 0);
    if (isContiguous) {
      for (var i = 0; i < count; i++) {
        result[i] = codec.read(data, i * codec.size);
      }
      return result;
    }
    final index = List<int>.filled(rank, 0);
    for (var i = 0; i < count; i++) {
      result[i] = codec.read(data, _elementOffset(index) * codec.size);
      for (var d = rank - 1; d >= 0; d--) {
        if (++index[d] < shape[d]) break;
        index[d] = 0;
      }
    }
    return result;
  }

  int _elementOffset(List<int> index) {
    final interleave = interleaveLayout;
    var offset = 0;
    for (var d = 0; d < rank; d++) {
      if (interleave != null && d == interleave.dimension) {
        offset +=
            (index[d] ~/ interleave.factor) * strides[d] +
            index[d] % interleave.factor;
      } else {
        offset += index[d] * strides[d];
      }
    }
    return offset;
  }

  @override
  String toString() => 'NDArray(${scalarType.name}, $shape)';
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

int _product(List<int> shape) => shape.fold(1, (a, b) => a * b);

void _checkShape(List<int> shape) {
  if (shape.any((d) => d < 0)) {
    throw ArgumentError.value(
      shape,
      'shape',
      'must not contain negative (dynamic) dimensions',
    );
  }
}

/// The number of storage elements a strided layout spans.
int _storageElements(
  List<int> shape,
  List<int> strides,
  InterleaveLayout? interleave,
) {
  if (shape.any((d) => d == 0)) return 0;
  var maxOffset = 0;
  for (var d = 0; d < shape.length; d++) {
    final last = shape[d] - 1;
    if (interleave != null && d == interleave.dimension) {
      maxOffset +=
          (last ~/ interleave.factor) * strides[d] +
          math.min<int>(interleave.factor, shape[d]) -
          1;
    } else {
      maxOffset += last * strides[d];
    }
  }
  return maxOffset + 1;
}

/// Reads and writes single elements of a byte-aligned scalar type.
final class _ElementCodec {
  const _ElementCodec(this.size, this.read, this.write);

  factory _ElementCodec.of(ScalarType type) => switch (type) {
    ScalarType.boolean => _ElementCodec(
      1,
      (d, o) => d.getUint8(o) == 0 ? 0 : 1,
      (d, o, v) => d.setUint8(o, v == 0 ? 0 : 1),
    ),
    ScalarType.int8 => _ElementCodec(
      1,
      (d, o) => d.getInt8(o),
      (d, o, v) => d.setInt8(o, v.toInt()),
    ),
    ScalarType.uint8 => _ElementCodec(
      1,
      (d, o) => d.getUint8(o),
      (d, o, v) => d.setUint8(o, v.toInt()),
    ),
    ScalarType.int16 => _ElementCodec(
      2,
      (d, o) => d.getInt16(o, Endian.little),
      (d, o, v) => d.setInt16(o, v.toInt(), Endian.little),
    ),
    ScalarType.uint16 => _ElementCodec(
      2,
      (d, o) => d.getUint16(o, Endian.little),
      (d, o, v) => d.setUint16(o, v.toInt(), Endian.little),
    ),
    ScalarType.int32 => _ElementCodec(
      4,
      (d, o) => d.getInt32(o, Endian.little),
      (d, o, v) => d.setInt32(o, v.toInt(), Endian.little),
    ),
    ScalarType.uint32 => _ElementCodec(
      4,
      (d, o) => d.getUint32(o, Endian.little),
      (d, o, v) => d.setUint32(o, v.toInt(), Endian.little),
    ),
    ScalarType.int64 => _ElementCodec(
      8,
      (d, o) => d.getInt64(o, Endian.little),
      (d, o, v) => d.setInt64(o, v.toInt(), Endian.little),
    ),
    ScalarType.uint64 => _ElementCodec(
      8,
      (d, o) => d.getUint64(o, Endian.little),
      (d, o, v) => d.setUint64(o, v.toInt(), Endian.little),
    ),
    ScalarType.float16 => _ElementCodec(
      2,
      (d, o) => halfBitsToDouble(d.getUint16(o, Endian.little)),
      (d, o, v) =>
          d.setUint16(o, doubleToHalfBits(v.toDouble()), Endian.little),
    ),
    ScalarType.bfloat16 => _ElementCodec(
      2,
      (d, o) => bfloat16BitsToDouble(d.getUint16(o, Endian.little)),
      (d, o, v) =>
          d.setUint16(o, doubleToBfloat16Bits(v.toDouble()), Endian.little),
    ),
    ScalarType.float32 => _ElementCodec(
      4,
      (d, o) => d.getFloat32(o, Endian.little),
      (d, o, v) => d.setFloat32(o, v.toDouble(), Endian.little),
    ),
    ScalarType.float64 => _ElementCodec(
      8,
      (d, o) => d.getFloat64(o, Endian.little),
      (d, o, v) => d.setFloat64(o, v.toDouble(), Endian.little),
    ),
    _ => throw UnsupportedError(
      '${type.name} has no Dart element representation; use NDArray.bytes.',
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

/// Decodes bfloat16 bits.
double bfloat16BitsToDouble(int bits) {
  final data = ByteData(4)..setUint32(0, (bits & 0xFFFF) << 16);
  return data.getFloat32(0);
}

/// Encodes [value] as bfloat16 bits, rounding to nearest even.
int doubleToBfloat16Bits(double value) {
  final bits = _float32Bits(value);
  if ((bits & 0x7FFFFFFF) > 0x7F800000) return ((bits >> 16) & 0x8000) | 0x7FC0;
  return ((bits + 0x7FFF + ((bits >> 16) & 1)) >> 16) & 0xFFFF;
}

int _float32Bits(double value) =>
    (ByteData(4)..setFloat32(0, value)).getUint32(0);

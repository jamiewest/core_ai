import 'messages.g.dart';

/// The element type of an [NDArray], mirroring Core AI's
/// `NDArray.ScalarType`.
///
/// Every type round-trips losslessly as raw bytes. Typed accessors such as
/// `NDArray.toDoubleList` are available for the byte-aligned types listed in
/// [isByteAligned]; sub-byte and 8-bit float types are exposed as raw storage.
enum ScalarType {
  /// A Boolean stored in one byte (0 is false).
  boolean(8, _Kind.boolean),

  /// 2-bit signed integer, range [-2, 1].
  int2(2, _Kind.signed),

  /// 3-bit signed integer, range [-4, 3].
  int3(3, _Kind.signed),

  /// 4-bit signed integer, range [-8, 7].
  int4(4, _Kind.signed),

  /// 5-bit signed integer, range [-16, 15].
  int5(5, _Kind.signed),

  /// 6-bit signed integer, range [-32, 31].
  int6(6, _Kind.signed),

  /// 7-bit signed integer, range [-64, 63].
  int7(7, _Kind.signed),

  /// 8-bit signed integer.
  int8(8, _Kind.signed),

  /// 16-bit signed integer.
  int16(16, _Kind.signed),

  /// 32-bit signed integer.
  int32(32, _Kind.signed),

  /// 64-bit signed integer.
  int64(64, _Kind.signed),

  /// 128-bit signed integer.
  int128(128, _Kind.signed),

  /// 1-bit unsigned integer, range [0, 1].
  uint1(1, _Kind.unsigned),

  /// 2-bit unsigned integer, range [0, 3].
  uint2(2, _Kind.unsigned),

  /// 3-bit unsigned integer, range [0, 7].
  uint3(3, _Kind.unsigned),

  /// 4-bit unsigned integer, range [0, 15].
  uint4(4, _Kind.unsigned),

  /// 5-bit unsigned integer, range [0, 31].
  uint5(5, _Kind.unsigned),

  /// 6-bit unsigned integer, range [0, 63].
  uint6(6, _Kind.unsigned),

  /// 7-bit unsigned integer, range [0, 127].
  uint7(7, _Kind.unsigned),

  /// 8-bit unsigned integer.
  uint8(8, _Kind.unsigned),

  /// 16-bit unsigned integer.
  uint16(16, _Kind.unsigned),

  /// 32-bit unsigned integer.
  uint32(32, _Kind.unsigned),

  /// 64-bit unsigned integer.
  uint64(64, _Kind.unsigned),

  /// 128-bit unsigned integer.
  uint128(128, _Kind.unsigned),

  /// FP8 with 5 exponent and 2 mantissa bits.
  float8e5m2(8, _Kind.float),

  /// FP8 with 4 exponent and 3 mantissa bits, finite only.
  float8e4m3fn(8, _Kind.float),

  /// FP8 scale type with 8 exponent bits and no mantissa.
  float8e8m0fn(8, _Kind.float),

  /// FP4 with 2 exponent bits and 1 mantissa bit.
  float4e2m1fn(4, _Kind.float),

  /// IEEE 754 half precision.
  float16(16, _Kind.float),

  /// IEEE 754 single precision.
  float32(32, _Kind.float),

  /// IEEE 754 double precision.
  float64(64, _Kind.float),

  /// Brain floating point: float32's exponent range with 7 mantissa bits.
  bfloat16(16, _Kind.float),

  /// Complex number with float16 real and imaginary parts.
  cfloat16(32, _Kind.complex),

  /// Complex number with float32 real and imaginary parts.
  cfloat32(64, _Kind.complex),

  /// Complex number with float64 real and imaginary parts.
  cfloat64(128, _Kind.complex);

  const ScalarType(this.bitWidth, this._kind);

  /// The number of bits one element occupies.
  final int bitWidth;
  final _Kind _kind;

  /// Whether each element occupies a whole number of bytes.
  bool get isByteAligned => bitWidth % 8 == 0;

  /// Whether this is a (real) floating-point type.
  bool get isFloatingPoint => _kind == _Kind.float;

  /// Whether this is a signed or unsigned integer type.
  bool get isInteger => _kind == _Kind.signed || _kind == _Kind.unsigned;

  /// Whether this is a signed integer type.
  bool get isSigned => _kind == _Kind.signed;

  /// Whether this is a complex type (interleaved real, imaginary pairs).
  bool get isComplex => _kind == _Kind.complex;

  /// Whether `NDArray.toDoubleList` / `NDArray.toIntList` can decode this
  /// type.
  bool get hasDartRepresentation => switch (this) {
    boolean ||
    int8 ||
    int16 ||
    int32 ||
    int64 ||
    uint8 ||
    uint16 ||
    uint32 ||
    uint64 ||
    float16 ||
    bfloat16 ||
    float32 ||
    float64 => true,
    _ => false,
  };

  /// The number of bytes needed to store [elementCount] densely packed
  /// elements.
  int byteCountFor(int elementCount) => (elementCount * bitWidth + 7) ~/ 8;

  ScalarTypeMessage get _message => ScalarTypeMessage.values[index];
}

enum _Kind { boolean, signed, unsigned, float, complex }

/// Conversions between the public [ScalarType] and its Pigeon message.
extension ScalarTypeMessageConversion on ScalarType {
  /// The Pigeon representation.
  ScalarTypeMessage toMessage() => _message;
}

/// Conversions from the Pigeon message to the public [ScalarType].
extension ScalarTypeFromMessage on ScalarTypeMessage {
  /// The public representation.
  ScalarType toScalarType() => ScalarType.values[index];
}

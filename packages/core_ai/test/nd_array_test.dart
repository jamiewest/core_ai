import 'dart:typed_data';

import 'package:core_ai/core_ai.dart';
import 'package:core_ai/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScalarType', () {
    test('mirrors the Pigeon enum one to one', () {
      expect(
        ScalarType.values.map((t) => t.name),
        ScalarTypeMessage.values.map((t) => t.name),
      );
    });

    test('reports sizes and categories', () {
      expect(ScalarType.float16.bitWidth, 16);
      expect(ScalarType.int4.isByteAligned, isFalse);
      expect(ScalarType.int4.byteCountFor(5), 3);
      expect(ScalarType.uint1.byteCountFor(9), 2);
      expect(ScalarType.cfloat32.isComplex, isTrue);
      expect(ScalarType.bfloat16.isFloatingPoint, isTrue);
      expect(ScalarType.uint8.isSigned, isFalse);
      expect(ScalarType.float8e4m3fn.hasDartRepresentation, isFalse);
    });
  });

  group('NDArray', () {
    test('typed constructors round-trip', () {
      expect(NDArray.float32([1.5, -2]).toDoubleList(), [1.5, -2]);
      expect(NDArray.float64([1e300]).toDoubleList(), [1e300]);
      expect(NDArray.int8([-128, 127]).toIntList(), [-128, 127]);
      expect(NDArray.int16([-3]).toIntList(), [-3]);
      expect(NDArray.int32([1 << 30]).toIntList(), [1 << 30]);
      expect(NDArray.int64([1 << 40]).toIntList(), [1 << 40]);
      expect(NDArray.uint8([255]).toIntList(), [255]);
      expect(NDArray.uint16([65535]).toIntList(), [65535]);
      expect(NDArray.uint32([4294967295]).toIntList(), [4294967295]);
      expect(NDArray.uint64([7]).toIntList(), [7]);
      expect(NDArray.boolean([true, false]).toBoolList(), [true, false]);
    });

    test('stores little-endian row-major bytes', () {
      final array = NDArray.int32([1, 2, 3, 4, 5, 6], shape: [2, 3]);
      expect(array.shape, [2, 3]);
      expect(array.strides, [3, 1]);
      expect(array.bytes.length, 24);
      expect(array.bytes.sublist(0, 8), [1, 0, 0, 0, 2, 0, 0, 0]);
      expect(array.isContiguous, isTrue);
      expect(array.elementAt([1, 2]), 6);
    });

    test('encodes float16 with round-to-nearest-even', () {
      int bits(double value) => ByteData.sublistView(
        NDArray.float16([value]).bytes,
      ).getUint16(0, Endian.little);
      expect(bits(1), 0x3C00);
      expect(bits(-2), 0xC000);
      expect(bits(65504), 0x7BFF);
      expect(bits(0.1), 0x2E66);
      expect(bits(1e6), 0x7C00);
      expect(bits(5.960464477539063e-8), 0x0001);
      expect(bits(1e-10), 0x0000);
      expect(bits(double.nan) & 0x7C00, 0x7C00);
      expect(NDArray.float16([0.5, 1024, -0.25]).toDoubleList(), [
        0.5,
        1024,
        -0.25,
      ]);
    });

    test('encodes bfloat16', () {
      final array = NDArray.bfloat16([1, -3.5, 1e38]);
      expect(
        ByteData.sublistView(array.bytes).getUint16(0, Endian.little),
        0x3F80,
      );
      final decoded = array.toDoubleList();
      expect(decoded[0], 1);
      expect(decoded[1], -3.5);
      expect(decoded[2], closeTo(1e38, 1e36));
    });

    test('reads strided layouts in logical order', () {
      // A [2, 2] view of column-major storage [1, 3, 2, 4].
      final array = NDArray.fromBytes(
        NDArray.float32([1, 3, 2, 4]).bytes,
        scalarType: ScalarType.float32,
        shape: [2, 2],
        strides: [1, 2],
      );
      expect(array.isContiguous, isFalse);
      expect(array.toDoubleList(), [1, 2, 3, 4]);
      expect(array.asFloat32List(), isNull);
      expect(array.toFloat32List(), [1, 2, 3, 4]);
    });

    test('reads interleaved layouts', () {
      // Logical [C=2, W=3] stored as interleaved channels: c0w0 c1w0 c0w1 ...
      final storage = NDArray.float32([0, 10, 1, 11, 2, 12]).bytes;
      final array = NDArray.fromBytes(
        storage,
        scalarType: ScalarType.float32,
        shape: [2, 3],
        strides: [2, 2],
        interleaveLayout: const InterleaveLayout(dimension: 0, factor: 2),
      );
      expect(array.toDoubleList(), [0, 1, 2, 10, 11, 12]);
      expect(array.elementAt([1, 2]), 12);
    });

    test('validates construction arguments', () {
      expect(
        () => NDArray.float32([1, 2, 3], shape: [2, 2]),
        throwsArgumentError,
      );
      expect(
        () => NDArray.zeros(ScalarType.float32, [-1]),
        throwsArgumentError,
      );
      expect(
        () => NDArray.fromBytes(
          Uint8List(4),
          scalarType: ScalarType.float32,
          shape: [2],
        ),
        throwsArgumentError,
      );
      expect(
        () => NDArray.fromBytes(
          Uint8List(8),
          scalarType: ScalarType.float32,
          shape: [2],
          strides: [1, 1],
        ),
        throwsArgumentError,
      );
      expect(() => NDArray.float32([1]).elementAt([1]), throwsRangeError);
    });

    test('keeps sub-byte types as raw storage', () {
      final array = NDArray.fromBytes(
        Uint8List.fromList([0x21, 0x03]),
        scalarType: ScalarType.int4,
        shape: [3],
      );
      expect(array.bytes, [0x21, 0x03]);
      expect(array.toDoubleList, throwsUnsupportedError);
      expect(NDArray.zeros(ScalarType.int4, [5]).bytes.length, 3);
    });

    test('reshapes contiguous data', () {
      final array = NDArray.float32([1, 2, 3, 4, 5, 6]).reshaped([3, 2]);
      expect(array.shape, [3, 2]);
      expect(array.elementAt([2, 1]), 6);
      expect(() => array.reshaped([4]), throwsArgumentError);
    });

    test('offers a zero-copy float32 view', () {
      final array = NDArray.float32([1, 2]);
      final view = array.asFloat32List()!;
      expect(view, [1, 2]);
      view[0] = 9;
      expect(array.toDoubleList(), [9, 2], reason: 'the view shares storage');
    });

    test('converts to and from messages', () {
      final array = NDArray.fromBytes(
        Uint8List(24),
        scalarType: ScalarType.float32,
        shape: [2, 2],
        strides: [3, 1],
      );
      final message = array.toMessage();
      expect(message.scalarType, ScalarTypeMessage.float32);
      expect(message.strides, [3, 1]);
      final back = NDArray.fromMessage(message);
      expect(back.strides, [3, 1]);
      expect(back.shape, [2, 2]);

      final contiguous = NDArray.fromMessage(
        NDArrayMessage(
          scalarType: ScalarTypeMessage.int8,
          shape: [2, 3],
          strides: [],
          data: Uint8List(6),
        ),
      );
      expect(contiguous.strides, [3, 1]);
    });
  });

  group('contiguousStrides', () {
    test('computes row-major strides', () {
      expect(contiguousStrides([2, 3, 4]), [12, 4, 1]);
      expect(contiguousStrides([]), isEmpty);
      expect(contiguousStrides([0, 5]), [5, 1]);
    });
  });
}

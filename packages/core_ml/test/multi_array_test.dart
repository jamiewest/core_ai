import 'dart:typed_data';

import 'package:core_ml/core_ml.dart';
import 'package:core_ml/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('float16', () {
    test('encodes exact values', () {
      expect(doubleToHalfBits(0), 0x0000);
      expect(doubleToHalfBits(-0.0), 0x8000);
      expect(doubleToHalfBits(1), 0x3C00);
      expect(doubleToHalfBits(-2), 0xC000);
      expect(doubleToHalfBits(0.5), 0x3800);
      expect(doubleToHalfBits(65504), 0x7BFF);
      expect(doubleToHalfBits(6.103515625e-05), 0x0400);
      expect(doubleToHalfBits(5.960464477539063e-08), 0x0001);
    });

    test('handles overflow, underflow, infinity and NaN', () {
      expect(doubleToHalfBits(1e6), 0x7C00);
      expect(doubleToHalfBits(double.infinity), 0x7C00);
      expect(doubleToHalfBits(double.negativeInfinity), 0xFC00);
      expect(doubleToHalfBits(1e-10), 0x0000);
      expect(halfBitsToDouble(doubleToHalfBits(double.nan)), isNaN);
    });

    test('rounds to nearest even', () {
      // 1 + 2^-11 is halfway between 1 and the next half; ties go to even.
      expect(doubleToHalfBits(1 + 1 / 2048), 0x3C00);
      expect(doubleToHalfBits(1 + 3 / 2048), 0x3C02);
      expect(doubleToHalfBits(1 + 1.1 / 2048), 0x3C01);
    });

    test('decodes', () {
      expect(halfBitsToDouble(0x3C00), 1);
      expect(halfBitsToDouble(0xC000), -2);
      expect(halfBitsToDouble(0x7BFF), 65504);
      expect(halfBitsToDouble(0x0001), 5.960464477539063e-08);
      expect(halfBitsToDouble(0x7C00), double.infinity);
      expect(halfBitsToDouble(0xFC00), double.negativeInfinity);
      expect(halfBitsToDouble(0x7E00), isNaN);
    });

    test('round-trips through MLMultiArray', () {
      final array = MLMultiArray.float16([1.5, -0.25, 1000, 3.14159]);
      expect(array.bytes.length, 8);
      expect(array.bytes.sublist(0, 2), [0x00, 0x3E]); // 1.5, little-endian
      final values = array.toDoubleList();
      expect(values.take(3), [1.5, -0.25, 1000]);
      expect(values[3], closeTo(3.14159, 1e-3));
    });
  });

  group('MLMultiArray', () {
    test('encodes every data type', () {
      final cases = {
        MLMultiArrayDataType.float16: MLMultiArray.float16([1, -2]),
        MLMultiArrayDataType.float32: MLMultiArray.float32([1, -2]),
        MLMultiArrayDataType.float64: MLMultiArray.float64([1, -2]),
        MLMultiArrayDataType.int32: MLMultiArray.int32([1, -2]),
        MLMultiArrayDataType.int8: MLMultiArray.int8([1, -2]),
      };
      for (final MapEntry(key: type, value: array) in cases.entries) {
        expect(array.dataType, type);
        expect(array.bytes.length, 2 * type.byteCount, reason: type.name);
        expect(array.toDoubleList(), [1, -2], reason: type.name);
        expect(array.toIntList(), [1, -2], reason: type.name);
      }
      expect(
        MLMultiArray.float32([1, 2]).bytes,
        Float32List.fromList([1, 2]).buffer.asUint8List(),
      );
      expect(
        MLMultiArray.int32([7]).bytes,
        Int32List.fromList([7]).buffer.asUint8List(),
      );
    });

    test('shape, count and element access', () {
      final array = MLMultiArray.float32([0, 1, 2, 3, 4, 5], shape: [2, 3]);
      expect(array.shape, [2, 3]);
      expect(array.strides, [3, 1]);
      expect(array.rank, 2);
      expect(array.count, 6);
      expect(array.isContiguous, isTrue);
      expect(array.elementAt([1, 2]), 5);
      expect(() => array.elementAt([2, 0]), throwsRangeError);
      expect(() => array.elementAt([0]), throwsRangeError);
      expect(array.asFloat32List(), [0, 1, 2, 3, 4, 5]);
      expect(array.reshaped([3, 2]).shape, [3, 2]);
      expect(() => array.reshaped([4]), throwsArgumentError);
    });

    test('decodes strided storage', () {
      // A 2x2 float32 array whose rows are padded to 3 elements, as Core ML
      // produces for pixel-buffer-backed outputs.
      final array = MLMultiArray.fromBytes(
        Float32List.fromList([1, 2, -1, 3, 4]).buffer.asUint8List(),
        dataType: MLMultiArrayDataType.float32,
        shape: [2, 2],
        strides: [3, 1],
      );
      expect(array.isContiguous, isFalse);
      expect(array.toDoubleList(), [1, 2, 3, 4]);
      expect(array.elementAt([1, 1]), 4);
      expect(array.asFloat32List(), isNull);
      expect(array.toFloat32List(), [1, 2, 3, 4]);
      expect(() => array.reshaped([4]), throwsStateError);
    });

    test('validates storage size and shapes', () {
      expect(
        () => MLMultiArray.fromBytes(
          Uint8List(8),
          dataType: MLMultiArrayDataType.float32,
          shape: [3],
        ),
        throwsArgumentError,
      );
      expect(
        () => MLMultiArray.fromBytes(
          Uint8List(4),
          dataType: MLMultiArrayDataType.float32,
          shape: [1],
          strides: [1, 1],
        ),
        throwsArgumentError,
      );
      expect(
        () => MLMultiArray.float32([1, 2], shape: [3]),
        throwsArgumentError,
      );
      expect(() => MLMultiArray.float32([], shape: [-1]), throwsArgumentError);
      expect(storageElements([2, 2], [3, 1]), 5);
      expect(storageElements([0, 4], [4, 1]), 0);
      expect(storageElements([], []), 1);
    });

    test('maps to and from messages', () {
      final array = MLMultiArray.float16([1, 2, 3, 4], shape: [2, 2]);
      final message = array.toMessage();
      expect(message.dataType, MultiArrayDataTypeMessage.float16);
      expect(message.shape, [2, 2]);
      expect(message.strides, [2, 1]);
      expect(message.data, array.bytes);

      final back = MLMultiArray.fromMessage(
        MultiArrayMessage(
          dataType: MultiArrayDataTypeMessage.int32,
          shape: [2],
          strides: [],
          data: Int32List.fromList([5, 6]).buffer.asUint8List(),
        ),
      );
      expect(back.dataType, MLMultiArrayDataType.int32);
      expect(back.strides, [1]);
      expect(back.toIntList(), [5, 6]);
    });

    test('data type enums stay aligned with messages', () {
      for (final type in MLMultiArrayDataType.values) {
        expect(type.toMessage().name, type.name);
      }
      for (final type in MLFeatureType.values) {
        expect(type.toMessage().name, type.name);
      }
      for (final units in MLComputeUnits.values) {
        expect(units.toMessage().name, units.name);
      }
    });
  });

  group('images', () {
    test('pixel formats', () {
      expect(PixelFormat.fourCC('BGRA'), PixelFormat.bgra32);
      expect(PixelFormat.describe(PixelFormat.bgra32), 'BGRA');
      expect(PixelFormat.describe(PixelFormat.rgb24), '0x00000018');
      expect(() => PixelFormat.fourCC('BGR'), throwsArgumentError);
    });

    test('converts RGBA pixels', () {
      final rgba = Uint8List.fromList([10, 20, 30, 255, 40, 50, 60, 128]);
      final bgra = PixelBuffer.fromRgba8888(rgba, width: 2, height: 1);
      expect(bgra.planes.single.bytes, [30, 20, 10, 255, 60, 50, 40, 128]);
      expect(bgra.planes.single.bytesPerRow, 8);
      expect(bgra.toRgba8888(), rgba);

      final gray = PixelBuffer.fromRgba8888(
        rgba,
        width: 2,
        height: 1,
        pixelFormatType: PixelFormat.oneComponent8,
      );
      expect(gray.planes.single.bytes, [18, 48]);
    });

    test('image inputs map to messages', () {
      final file =
          const ImageInput.file('/tmp/a.png', width: 8).toMessage()
              as EncodedImageMessage;
      expect(file.path, '/tmp/a.png');
      expect(file.bytes, isNull);
      expect(file.width, 8);

      final encoded =
          ImageInput.encoded(Uint8List.fromList([1, 2])).toMessage()
              as EncodedImageMessage;
      expect(encoded.bytes, [1, 2]);
      expect(encoded.path, isNull);

      final pixels =
          ImageInput.pixels(
                width: 1,
                height: 2,
                bytes: Uint8List(8),
              ).toMessage()
              as PixelBufferMessage;
      expect(pixels.pixelFormatType, PixelFormat.bgra32);
      expect(pixels.planes.single.bytesPerRow, 4);
      expect(
        () => PixelBuffer.packed(
          width: 2,
          height: 2,
          pixelFormatType: PixelFormat.bgra32,
          bytes: Uint8List(8),
          bytesPerRow: 8,
        ),
        throwsArgumentError,
      );
    });
  });
}

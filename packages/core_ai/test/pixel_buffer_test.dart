import 'dart:typed_data';

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rgba = Uint8List.fromList([
    10, 20, 30, 255, //
    40, 50, 60, 128,
  ]);

  test('four-character codes', () {
    expect(PixelFormat.fourCC('BGRA'), PixelFormat.bgra32);
    expect(PixelFormat.fourCC('L008'), PixelFormat.oneComponent8);
    expect(PixelFormat.describe(PixelFormat.bgra32), 'BGRA');
    expect(PixelFormat.describe(PixelFormat.argb32), '0x00000020');
    expect(() => PixelFormat.fourCC('BGR'), throwsArgumentError);
  });

  test('converts RGBA8888 to BGRA and back', () {
    final buffer = PixelBuffer.fromRgba8888(rgba, width: 2, height: 1);
    expect(buffer.pixelFormatType, PixelFormat.bgra32);
    expect(buffer.planes.single.bytes, [30, 20, 10, 255, 60, 50, 40, 128]);
    expect(buffer.toRgba8888(), rgba);
  });

  test('converts to other packed formats', () {
    expect(
      PixelBuffer.fromRgba8888(
        rgba,
        width: 2,
        height: 1,
        pixelFormatType: PixelFormat.argb32,
      ).planes.single.bytes.sublist(0, 4),
      [255, 10, 20, 30],
    );
    final rgb = PixelBuffer.fromRgba8888(
      rgba,
      width: 2,
      height: 1,
      pixelFormatType: PixelFormat.rgb24,
    );
    expect(rgb.planes.single.bytesPerRow, 6);
    expect(rgb.toRgba8888(), [10, 20, 30, 255, 40, 50, 60, 255]);

    final gray = PixelBuffer.fromRgba8888(
      Uint8List.fromList([255, 255, 255, 255]),
      width: 1,
      height: 1,
      pixelFormatType: PixelFormat.oneComponent8,
    );
    expect(gray.planes.single.bytes, [255]);
    expect(gray.toRgba8888(), [255, 255, 255, 255]);
  });

  test('respects row padding when reading', () {
    final padded = PixelBuffer.packed(
      width: 1,
      height: 2,
      pixelFormatType: PixelFormat.bgra32,
      bytesPerRow: 8,
      bytes: Uint8List.fromList([
        3, 2, 1, 255, 0, 0, 0, 0, //
        6, 5, 4, 255, 0, 0, 0, 0,
      ]),
    );
    expect(padded.toRgba8888(), [1, 2, 3, 255, 4, 5, 6, 255]);
  });

  test('rejects unsupported conversions', () {
    expect(
      () => PixelBuffer.fromRgba8888(
        rgba,
        width: 2,
        height: 1,
        pixelFormatType: PixelFormat.rgba128Float,
      ),
      throwsUnsupportedError,
    );
    expect(
      () => PixelBuffer.fromRgba8888(rgba, width: 4, height: 4),
      throwsArgumentError,
    );
  });

  test('converts to and from messages', () {
    final buffer = PixelBuffer.fromRgba8888(rgba, width: 2, height: 1);
    final back = PixelBuffer.fromMessage(buffer.toMessage());
    expect(back.width, 2);
    expect(back.planes.single.bytesPerRow, 8);
    expect(back.toRgba8888(), rgba);
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Extracts bundled audio/model fixtures into a private temporary directory.
/// Call [dispose] after all file analyses finish.
class SoundFixtures {
  SoundFixtures._(this.directory);

  /// Directory owning the extracted files.
  final Directory directory;

  /// Speech WAV file.
  String get speech => '${directory.path}/speech.wav';

  /// 550 Hz tone WAV file.
  String get tone => '${directory.path}/tone.wav';

  /// Tiny custom Core ML classifier trained to distinguish speech and tone.
  String get model => '${directory.path}/SpeechOrTone.mlmodel';

  /// Copies assets without requiring filesystem permissions from the user.
  static Future<SoundFixtures> load() async {
    final directory = await Directory.systemTemp.createTemp('sound_analysis_');
    try {
      for (final name in ['speech.wav', 'tone.wav', 'SpeechOrTone.mlmodel']) {
        final data = await rootBundle.load('assets/$name');
        await File('${directory.path}/$name').writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      return SoundFixtures._(directory);
    } on Object {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  /// Deletes only this instance's temporary files.
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

/// Decodes the bundled mono, 16 kHz, signed 16-bit RIFF/WAVE fixtures.
/// This is deliberately a fixture decoder, not a general audio codec.
Float32List decodeFixtureWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  String tag(int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Expected a RIFF/WAVE fixture.');
  }
  var validFormat = false;
  Uint8List? pcm;
  for (var offset = 12; offset + 8 <= bytes.length;) {
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (start + size > bytes.length) {
      throw const FormatException('Truncated WAV.');
    }
    if (tag(offset) == 'fmt ') {
      validFormat =
          size >= 16 &&
          data.getUint16(start, Endian.little) == 1 &&
          data.getUint16(start + 2, Endian.little) == 1 &&
          data.getUint32(start + 4, Endian.little) == 16000 &&
          data.getUint16(start + 14, Endian.little) == 16;
    } else if (tag(offset) == 'data') {
      pcm = Uint8List.sublistView(bytes, start, start + size);
    }
    offset = start + size + (size & 1);
  }
  if (!validFormat || pcm == null || pcm.length.isOdd) {
    throw const FormatException('Expected mono 16 kHz 16-bit PCM.');
  }
  final samples = ByteData.sublistView(pcm);
  return Float32List.fromList([
    for (var i = 0; i < pcm.length; i += 2)
      samples.getInt16(i, Endian.little) / 32768,
  ]);
}

import 'dart:io';
import 'package:flutter/services.dart';

/// Owns an extracted copy of the bundled synthetic speech sample.
class SpeechFixture {
  SpeechFixture._(this.directory);

  /// Temporary directory owned by this instance.
  final Directory directory;

  /// WAV file, mono signed 16-bit PCM at 16 kHz.
  String get path => '${directory.path}/speech.wav';

  /// Expected words, synthesized with the macOS Samantha voice.
  static const transcript =
      'The quick brown fox jumps over the lazy dog. '
      'Today is a beautiful day for a walk in the park.';

  /// Extracts the sample without user filesystem access.
  static Future<SpeechFixture> load() async {
    final directory = await Directory.systemTemp.createTemp('speech_example_');
    final fixture = SpeechFixture._(directory);
    try {
      final data = await rootBundle.load('assets/speech.wav');
      await File(fixture.path).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return fixture;
    } on Object {
      await fixture.dispose();
      rethrow;
    }
  }

  /// Deletes the extracted file after its analysis finishes.
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_intelligence/media_intelligence.dart';

/// Copies the bundled sample media into a private temporary directory, since
/// MediaIntelligence reads files. Call [dispose] when done.
class MediaFixtures {
  MediaFixtures._(this.directory);

  /// The directory holding the copies.
  final Directory directory;

  /// A 6-second clip: a blue scene with a moving circle, then a cut to a red
  /// scene with moving squares at 3 seconds.
  MediaAsset get clip => MediaAsset(id: 'clip', path: _path('clip.mp4'));

  /// A drawn landscape with no faces.
  MediaAsset get scene => MediaAsset(id: 'scene', path: _path('scene.png'));

  /// A fresh directory for a face library.
  String get libraryDirectory => _path('faces');

  String _path(String name) => '${directory.path}/$name';

  /// Copies the assets.
  static Future<MediaFixtures> load() async {
    final directory = await Directory.systemTemp.createTemp('media_intel_');
    try {
      for (final name in ['clip.mp4', 'scene.png']) {
        final data = await rootBundle.load('assets/$name');
        await File('${directory.path}/$name').writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      return MediaFixtures._(directory);
    } on Object {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  /// Deletes the copies.
  Future<void> dispose() => directory.delete(recursive: true);
}

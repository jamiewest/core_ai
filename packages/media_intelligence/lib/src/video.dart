import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'errors.dart';
import 'face_groups.dart';
import 'messages.g.dart';

/// A span of a video.
@immutable
final class VideoTimeRange {
  /// Creates a range.
  const VideoTimeRange(this.start, this.duration);

  /// Converts the Pigeon representation.
  VideoTimeRange.fromMessage(TimeRangeMessage message)
    : start = _duration(message.startSeconds),
      duration = _duration(message.durationSeconds);

  /// Where the range starts.
  final Duration start;

  /// How long it lasts.
  final Duration duration;

  /// Where the range ends.
  Duration get end => start + duration;

  static Duration _duration(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );

  @override
  bool operator ==(Object other) =>
      other is VideoTimeRange &&
      other.start == start &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(start, duration);

  @override
  String toString() => 'VideoTimeRange($start, $duration)';
}

/// How interesting one span of a video is.
@immutable
final class HighlightLevel {
  /// Creates a level.
  const HighlightLevel(this.range, this.level);

  /// The span.
  final VideoTimeRange range;

  /// Apple's score for the span. On the test clips this was 0 outside the
  /// highlights and 1 inside them.
  final double level;
}

/// The result of highlight analysis (Apple's
/// `HighlightAnalysisRequest.Result`).
@immutable
final class HighlightAnalysis {
  /// Creates a result.
  const HighlightAnalysis({required this.highlights, required this.levels});

  /// The spans worth showing, in order.
  final List<VideoTimeRange> highlights;

  /// A score for every span of the video, in order.
  final List<HighlightLevel> levels;
}

/// What [VideoAnalyzer.analyze] found. Each requested analysis succeeds or
/// fails on its own.
@immutable
final class VideoAnalysis {
  /// Converts the Pigeon representation.
  VideoAnalysis.fromMessage(VideoAnalysisMessage message)
    : highlights = message.highlights == null
          ? null
          : HighlightAnalysis(
              highlights: List.unmodifiable(
                message.highlights!.map(VideoTimeRange.fromMessage),
              ),
              levels: List.unmodifiable([
                for (final level in message.highlightLevels ?? const [])
                  HighlightLevel(
                    VideoTimeRange.fromMessage(level.range),
                    level.level,
                  ),
              ]),
            ),
      highlightsError = _error(message.highlightError),
      keyFrame = message.keyFrameSeconds == null
          ? null
          : VideoTimeRange._duration(message.keyFrameSeconds!),
      keyFrameError = _error(message.keyFrameError);

  /// The highlights, if requested and successful.
  final HighlightAnalysis? highlights;

  /// Why highlight analysis failed, if it did.
  final MediaIntelligenceException? highlightsError;

  /// The time of the most representative frame, if requested and
  /// successful. Use it as a thumbnail.
  final Duration? keyFrame;

  /// Why key frame analysis failed, if it did.
  final MediaIntelligenceException? keyFrameError;

  static MediaIntelligenceException? _error(RequestErrorMessage? message) =>
      message == null ? null : MediaIntelligenceException.fromMessage(message);
}

/// Finds highlights and key frames in videos (Apple's `VideoAnalyzer`,
/// iOS 27 / macOS 27).
abstract final class VideoAnalyzer {
  /// Analyzes the video at [video].
  ///
  /// Request [highlights], a [keyFrame], or both. Running both in one call is
  /// cheaper than two calls. Analysis runs on the device and can take many
  /// seconds; the framework offers no way to cancel it. An unreadable video
  /// is reported per analysis in the result, not thrown.
  static Future<VideoAnalysis> analyze(
    MediaAsset video, {
    bool highlights = true,
    bool keyFrame = true,
  }) async {
    final host = MediaIntelligenceBindings.instance.host;
    final message = await guardPlatformCall(
      () => host.analyzeVideo(video.toMessage(), highlights, keyFrame),
    );
    return VideoAnalysis.fromMessage(message);
  }
}

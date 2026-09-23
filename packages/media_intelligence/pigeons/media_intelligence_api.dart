// Pigeon schema for the media_intelligence plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/media_intelligence_api.dart
//   dart format lib/src/messages.g.dart
//
// Face analyzers are handles. Inserting and identifying assets stream one
// result per asset through `MediaIntelligenceCallbackApi`, keyed by a request
// id chosen in Dart.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'darwin/media_intelligence/Sources/media_intelligence/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'MediaIntelligencePigeonError'),
    dartPackageName: 'media_intelligence',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Mirrors `MediaIntelligenceImageAsset` / `MediaIntelligenceVideoAsset`
/// with a file URL.
class AssetMessage {
  AssetMessage({required this.id, required this.path});

  String id;
  String path;
}

/// Mirrors `FaceGroupAnalyzer.Face`.
class FaceMessage {
  FaceMessage({
    required this.id,
    required this.assetId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  String id;
  String assetId;
  String? entityId;
  double x;
  double y;
  double width;
  double height;
}

/// Faces grouped under one key: an asset id or an entity id.
class FaceGroupMessage {
  FaceGroupMessage({required this.key, required this.faces});

  String key;
  List<FaceMessage> faces;
}

/// Asset ids grouped under an entity id.
class AssetGroupMessage {
  AssetGroupMessage({required this.entityId, required this.assetIds});

  String entityId;
  List<String> assetIds;
}

/// Mirrors `FaceGroupAnalyzer.State`.
enum FaceGroupStateMessage { ready, stale, updating }

/// A time range in seconds.
class TimeRangeMessage {
  TimeRangeMessage({required this.startSeconds, required this.durationSeconds});

  double startSeconds;
  double durationSeconds;
}

/// Mirrors `HighlightAnalysisRequest.Result.levels`.
class HighlightLevelMessage {
  HighlightLevelMessage({required this.range, required this.level});

  TimeRangeMessage range;
  double level;
}

/// A failure of one video request, while others may succeed.
class RequestErrorMessage {
  RequestErrorMessage({required this.code, required this.message});

  String code;
  String message;
  String? details;
}

/// The results of `VideoAnalyzer.analyze`. A requested analysis has either
/// its result fields or its error set.
class VideoAnalysisMessage {
  VideoAnalysisMessage();

  List<TimeRangeMessage>? highlights;
  List<HighlightLevelMessage>? highlightLevels;
  RequestErrorMessage? highlightError;
  double? keyFrameSeconds;
  RequestErrorMessage? keyFrameError;
}

/// Always available, so Dart can ask whether the framework exists.
@HostApi()
abstract class MediaIntelligencePlatformApi {
  bool isSupported();
}

/// Registered only on iOS 27 / macOS 27 and later.
@HostApi()
abstract class MediaIntelligenceHostApi {
  // Face groups.
  @async
  int openFaceGroupAnalyzer(String workingDirectory);

  @async
  void purgeFaceGroups(String workingDirectory);

  @async
  FaceGroupStateMessage faceGroupState(int handle);

  /// Starts adding or re-analyzing assets. Returns once started; one
  /// `onAssetFaces` per asset follows, then `onComplete` or `onError`.
  @async
  void startInsertOrUpdateAssets(
    int handle,
    int requestId,
    List<AssetMessage> assets,
  );

  /// Like [startInsertOrUpdateAssets], without adding the assets.
  @async
  void startIdentifyFaces(int handle, int requestId, List<AssetMessage> assets);

  /// Stops routing results for [requestId]. The framework may still finish
  /// the work.
  void cancel(int requestId);

  @async
  void deleteAssets(int handle, List<String> assetIds);

  @async
  void deleteAllAssets(int handle);

  @async
  void updateFaceGroups(int handle);

  @async
  List<String> allAssetIds(int handle);

  @async
  List<String> allEntityIds(int handle);

  @async
  List<FaceMessage> allFaces(int handle);

  @async
  List<AssetGroupMessage> allAssetIdsByEntity(int handle);

  @async
  List<FaceGroupMessage> allFacesByEntity(int handle);

  @async
  List<FaceMessage> facesWithIds(int handle, List<String> faceIds);

  @async
  List<FaceGroupMessage> facesForEntities(int handle, List<String> entityIds);

  @async
  List<FaceGroupMessage> facesInAssets(int handle, List<String> assetIds);

  @async
  List<AssetGroupMessage> assetIdsForEntities(
    int handle,
    List<String> entityIds,
  );

  // Video.
  @async
  VideoAnalysisMessage analyzeVideo(
    AssetMessage asset,
    bool highlights,
    bool keyFrame,
  );

  // Handles.
  @async
  void release(int handle);

  @async
  int releaseAll();

  int liveHandleCount();
}

/// Native → Dart events for streaming face requests.
@FlutterApi()
abstract class MediaIntelligenceCallbackApi {
  void onAssetFaces(int requestId, FaceGroupMessage assetFaces);

  void onComplete(int requestId);

  void onError(int requestId, RequestErrorMessage error);
}

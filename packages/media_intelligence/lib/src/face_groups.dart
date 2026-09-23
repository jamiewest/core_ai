import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

/// An image or video file identified by an id you choose.
///
/// Ids are how results refer back to your media, so keep them stable, for
/// example a database key or a photo library identifier.
@immutable
final class MediaAsset {
  /// Creates an asset for the file at [path].
  const MediaAsset({required this.id, required this.path});

  /// Your identifier for the asset.
  final String id;

  /// The file's path.
  final String path;

  /// The Pigeon representation.
  AssetMessage toMessage() => AssetMessage(id: id, path: path);

  @override
  String toString() => 'MediaAsset($id)';
}

/// A detected face (Apple's `FaceGroupAnalyzer.Face`).
@immutable
final class Face {
  /// Converts the Pigeon representation.
  Face.fromMessage(FaceMessage message)
    : id = message.id,
      assetId = message.assetId,
      entityId = message.entityId,
      bounds = Rect.fromLTWH(
        message.x,
        message.y,
        message.width,
        message.height,
      );

  /// The face's identifier.
  final String id;

  /// The [MediaAsset.id] of the image it is in.
  final String assetId;

  /// The person it was grouped into, or null if it is not grouped yet.
  final String? entityId;

  /// Where the face is, exactly as Apple reports its `CGRect`.
  final Rect bounds;

  @override
  String toString() => 'Face($id in $assetId, entity: $entityId)';
}

/// The faces found in one asset.
@immutable
final class AssetFaces {
  /// Creates a result.
  const AssetFaces(this.assetId, this.faces);

  /// Converts the Pigeon representation.
  AssetFaces.fromMessage(FaceGroupMessage message)
    : assetId = message.key,
      faces = List.unmodifiable(message.faces.map(Face.fromMessage));

  /// The [MediaAsset.id].
  final String assetId;

  /// Its faces. Empty when the image has none.
  final List<Face> faces;
}

/// Whether the face groups reflect the latest assets
/// (Apple's `FaceGroupAnalyzer.State`).
enum FaceGroupState {
  /// Groups are up to date.
  ready,

  /// Assets changed since the last [FaceGroupAnalyzer.update].
  stale,

  /// An update is running.
  updating,
}

/// Groups the faces in a library of images into people
/// (Apple's `FaceGroupAnalyzer`, iOS 27 / macOS 27).
///
/// The library is stored in a working directory you own, and persists across
/// launches: open the same directory again to continue. Add images with
/// [insertOrUpdate], call [update] to regroup, then query faces, people
/// ("entities") and assets. Call [dispose] when done.
final class FaceGroupAnalyzer {
  FaceGroupAnalyzer._(this._bindings, this._handle, this.workingDirectory) {
    _bindings.finalizer.attach(this, _handle, detach: this);
  }

  /// Opens, or creates, the library in [workingDirectory].
  static Future<FaceGroupAnalyzer> open(String workingDirectory) async {
    final bindings = MediaIntelligenceBindings.instance;
    final handle = await guardPlatformCall(
      () => bindings.host.openFaceGroupAnalyzer(workingDirectory),
    );
    return FaceGroupAnalyzer._(bindings, handle, workingDirectory);
  }

  /// Deletes the library stored in [workingDirectory].
  ///
  /// Dispose analyzers open on it first.
  static Future<void> purge(String workingDirectory) => guardPlatformCall(
    () => MediaIntelligenceBindings.instance.host.purgeFaceGroups(
      workingDirectory,
    ),
  );

  final MediaIntelligenceBindings _bindings;
  final int _handle;
  bool _disposed = false;

  /// Where the library is stored.
  final String workingDirectory;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// The native handle. Throws a [StateError] after [dispose].
  int get handle {
    if (_disposed) {
      throw StateError('FaceGroupAnalyzer was used after being disposed.');
    }
    return _handle;
  }

  MediaIntelligenceHostApi get _host => _bindings.host;

  /// Whether the groups reflect the latest assets.
  Future<FaceGroupState> state() async {
    final state = await guardPlatformCall(() => _host.faceGroupState(handle));
    return FaceGroupState.values[state.index];
  }

  /// Adds [assets] to the library, or re-analyzes them if their ids are
  /// already in it, emitting the faces found in each.
  ///
  /// The work starts when the stream is listened to. Cancelling the
  /// subscription stops the events, although the framework may still finish
  /// processing. Asset ids must be unique and every file must exist.
  Stream<AssetFaces> insertOrUpdate(List<MediaAsset> assets) => _stream(
    (host, handle, requestId, messages) =>
        host.startInsertOrUpdateAssets(handle, requestId, messages),
    assets,
  );

  /// Finds faces in [assets] and matches them to the library's people,
  /// without adding the assets.
  ///
  /// Behaves like [insertOrUpdate] otherwise.
  Stream<AssetFaces> identifyFaces(List<MediaAsset> assets) => _stream(
    (host, handle, requestId, messages) =>
        host.startIdentifyFaces(handle, requestId, messages),
    assets,
  );

  /// Regroups faces into people after assets changed.
  Future<void> update() =>
      guardPlatformCall(() => _host.updateFaceGroups(handle));

  /// Removes assets, and their faces, from the library.
  Future<void> deleteAssets(List<String> assetIds) =>
      guardPlatformCall(() => _host.deleteAssets(handle, assetIds));

  /// Removes every asset from the library.
  Future<void> deleteAllAssets() =>
      guardPlatformCall(() => _host.deleteAllAssets(handle));

  /// The ids of the stored assets that contain faces.
  Future<List<String>> assetIds() =>
      guardPlatformCall(() => _host.allAssetIds(handle));

  /// The ids of the people found.
  Future<List<String>> entityIds() =>
      guardPlatformCall(() => _host.allEntityIds(handle));

  /// Every stored face.
  Future<List<Face>> faces() async =>
      _faces(await guardPlatformCall(() => _host.allFaces(handle)));

  /// The faces with [faceIds].
  Future<List<Face>> facesWithIds(List<String> faceIds) async => _faces(
    await guardPlatformCall(() => _host.facesWithIds(handle, faceIds)),
  );

  /// Each person's assets, keyed by entity id.
  Future<Map<String, List<String>>> assetIdsByEntity() async => _assetGroups(
    await guardPlatformCall(() => _host.allAssetIdsByEntity(handle)),
  );

  /// The assets of the people with [entityIds], keyed by entity id.
  Future<Map<String, List<String>>> assetIdsForEntities(
    List<String> entityIds,
  ) async => _assetGroups(
    await guardPlatformCall(() => _host.assetIdsForEntities(handle, entityIds)),
  );

  /// Each person's faces, keyed by entity id.
  Future<Map<String, List<Face>>> facesByEntity() async => _faceGroups(
    await guardPlatformCall(() => _host.allFacesByEntity(handle)),
  );

  /// The faces of the people with [entityIds], keyed by entity id.
  Future<Map<String, List<Face>>> facesForEntities(
    List<String> entityIds,
  ) async => _faceGroups(
    await guardPlatformCall(() => _host.facesForEntities(handle, entityIds)),
  );

  /// The faces in the assets with [assetIds], keyed by asset id.
  Future<Map<String, List<Face>>> facesInAssets(List<String> assetIds) async =>
      _faceGroups(
        await guardPlatformCall(() => _host.facesInAssets(handle, assetIds)),
      );

  /// Releases the native analyzer. The library stays on disk; see [purge].
  /// Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bindings.finalizer.detach(this);
    await guardPlatformCall(() => _host.release(_handle));
  }

  Stream<AssetFaces> _stream(
    Future<void> Function(
      MediaIntelligenceHostApi host,
      int handle,
      int requestId,
      List<AssetMessage> assets,
    )
    start,
    List<MediaAsset> assets,
  ) {
    final bindings = _bindings;
    final requestId = bindings.nextRequestId();
    late final StreamController<AssetFaces> controller;
    var finished = false;
    void finish() {
      if (finished) return;
      finished = true;
      bindings.unregisterRequest(requestId);
      unawaited(controller.close());
    }

    controller = StreamController<AssetFaces>(
      onListen: () async {
        final int id;
        try {
          id = handle;
        } on StateError catch (error, stack) {
          controller.addError(error, stack);
          finish();
          return;
        }
        bindings.registerRequest(requestId, _RequestSink(controller, finish));
        try {
          await guardPlatformCall(
            () => start(bindings.host, id, requestId, [
              for (final asset in assets) asset.toMessage(),
            ]),
          );
        } on MediaIntelligenceException catch (error, stack) {
          if (!finished) controller.addError(error, stack);
          finish();
        }
      },
      onCancel: () async {
        if (finished) return;
        finish();
        await guardPlatformCall(() async => bindings.host.cancel(requestId));
      },
    );
    return controller.stream;
  }

  static List<Face> _faces(List<FaceMessage> list) =>
      List.unmodifiable(list.map(Face.fromMessage));

  static Map<String, List<String>> _assetGroups(List<AssetGroupMessage> list) =>
      {
        for (final group in list)
          group.entityId: List<String>.unmodifiable(group.assetIds),
      };

  static Map<String, List<Face>> _faceGroups(List<FaceGroupMessage> list) => {
    for (final group in list) group.key: _faces(group.faces),
  };
}

class _RequestSink implements FaceRequestSink {
  _RequestSink(this._controller, this._finish);

  final StreamController<AssetFaces> _controller;
  final void Function() _finish;

  @override
  void onAssetFaces(FaceGroupMessage assetFaces) =>
      _controller.add(AssetFaces.fromMessage(assetFaces));

  @override
  void onComplete() => _finish();

  @override
  void onError(RequestErrorMessage error) {
    _controller.addError(MediaIntelligenceException.fromMessage(error));
    _finish();
  }
}

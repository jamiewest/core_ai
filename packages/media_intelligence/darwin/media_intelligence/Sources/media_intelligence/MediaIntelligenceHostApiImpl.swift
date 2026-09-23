#if canImport(MediaIntelligence)
  import CoreMedia
  import Foundation
  import MediaIntelligence

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Owns the face analyzers handed to Dart and the running face requests.
  @available(iOS 27.0, macOS 27.0, *)
  final class Registry: @unchecked Sendable {
    private struct Request {
      let handle: Int64
      var task: Task<Void, Never>?
    }

    private let lock = NSLock()
    private var nextHandle: Int64 = 1
    private var analyzers: [Int64: FaceGroupAnalyzer] = [:]
    private var requests: [Int64: Request] = [:]

    func insert(_ analyzer: FaceGroupAnalyzer) -> Int64 {
      lock.withLock {
        let handle = nextHandle
        nextHandle += 1
        analyzers[handle] = analyzer
        return handle
      }
    }

    func analyzer(_ handle: Int64) throws -> FaceGroupAnalyzer {
      guard let analyzer = lock.withLock({ analyzers[handle] }) else {
        throw Errors.invalidHandle(handle)
      }
      return analyzer
    }

    /// Removes an analyzer and cancels its requests. Returns false if unknown.
    @discardableResult
    func remove(_ handle: Int64) -> Bool {
      let (found, tasks) = lock.withLock { () -> (Bool, [Task<Void, Never>]) in
        let found = analyzers.removeValue(forKey: handle) != nil
        let ids = requests.filter { $0.value.handle == handle }.map(\.key)
        return (found, ids.compactMap { requests.removeValue(forKey: $0)?.task ?? nil })
      }
      tasks.forEach { $0.cancel() }
      return found
    }

    func removeAll() -> Int {
      let (count, tasks) = lock.withLock { () -> (Int, [Task<Void, Never>]) in
        let count = analyzers.count
        let tasks = requests.values.compactMap(\.task)
        analyzers.removeAll()
        requests.removeAll()
        return (count, tasks)
      }
      tasks.forEach { $0.cancel() }
      return count
    }

    var count: Int { lock.withLock { analyzers.count } }

    /// Reserves [requestId] before its task starts, so a task that ends at
    /// once still finds itself registered.
    func reserve(_ requestId: Int64, handle: Int64) throws {
      try lock.withLock {
        guard requests[requestId] == nil else {
          throw Errors.invalidArgument("Request \(requestId) is already running.")
        }
        requests[requestId] = Request(handle: handle)
      }
    }

    /// Attaches the task of a reserved request; cancels it if the request was
    /// cancelled or finished meanwhile.
    func attach(_ requestId: Int64, task: Task<Void, Never>) {
      let live = lock.withLock { () -> Bool in
        guard requests[requestId] != nil else { return false }
        requests[requestId]?.task = task
        return true
      }
      if !live { task.cancel() }
    }

    /// Whether [requestId] is still wanted by Dart.
    func isActive(_ requestId: Int64) -> Bool { lock.withLock { requests[requestId] != nil } }

    /// Stops routing [requestId]. Returns false if it had already finished.
    @discardableResult
    func finish(_ requestId: Int64) -> Bool {
      lock.withLock { requests.removeValue(forKey: requestId) != nil }
    }

    func cancel(_ requestId: Int64) {
      lock.withLock { requests.removeValue(forKey: requestId) }?.task?.cancel()
    }
  }

  /// Implements `MediaIntelligenceHostApi` on top of MediaIntelligence.
  @available(iOS 27.0, macOS 27.0, *)
  final class MediaIntelligenceHostApiImpl: MediaIntelligenceHostApi, @unchecked Sendable {
    private let registry = Registry()
    private let callback: MediaIntelligenceCallbackApi

    init(callback: MediaIntelligenceCallbackApi) {
      self.callback = callback
    }

    func shutdown() { _ = registry.removeAll() }

    // MARK: - Face groups

    func openFaceGroupAnalyzer(workingDirectory: String) async throws -> Int64 {
      try await translatingErrors {
        let url = try Self.directoryURL(workingDirectory)
        return registry.insert(try FaceGroupAnalyzer(workingDirectory: url))
      }
    }

    func purgeFaceGroups(workingDirectory: String) async throws {
      try await translatingErrors {
        try await FaceGroupAnalyzer.purge(workingDirectory: try Self.directoryURL(workingDirectory))
      }
    }

    func faceGroupState(handle: Int64) async throws -> FaceGroupStateMessage {
      try await translatingErrors {
        switch try await registry.analyzer(handle).state {
        case .ready: .ready
        case .stale: .stale
        case .updating: .updating
        @unknown default: .stale
        }
      }
    }

    func startInsertOrUpdateAssets(handle: Int64, requestId: Int64, assets: [AssetMessage])
      async throws
    {
      try await translatingErrors {
        let analyzer = try registry.analyzer(handle)
        let native = try Self.imageAssets(assets)
        try startStreaming(handle: handle, requestId: requestId) {
          try await analyzer.insertOrUpdateAssets(native)
        }
      }
    }

    func startIdentifyFaces(handle: Int64, requestId: Int64, assets: [AssetMessage]) async throws {
      try await translatingErrors {
        let analyzer = try registry.analyzer(handle)
        let native = try Self.imageAssets(assets)
        try startStreaming(handle: handle, requestId: requestId) {
          try await analyzer.identifyFaces(in: native)
        }
      }
    }

    /// Runs a per-asset face sequence, sending each element to Dart in order.
    private func startStreaming<S: AsyncSequence>(
      handle: Int64, requestId: Int64, _ makeSequence: @escaping @Sendable () async throws -> S
    ) throws
    where S.Element == (assetID: MediaIntelligenceImageAsset.ID, faces: [FaceGroupAnalyzer.Face]) {
      let registry = registry
      let callback = callback
      try registry.reserve(requestId, handle: handle)
      let task = Task {
        do {
          for try await (assetID, faces) in try await makeSequence() {
            try Task.checkCancellation()
            guard registry.isActive(requestId) else { return }
            let message = FaceGroupMessage(key: assetID.rawValue, faces: faces.map(Self.message))
            try? await callback.onAssetFaces(requestId: requestId, assetFaces: message)
          }
          guard registry.finish(requestId) else { return }
          try? await callback.onComplete(requestId: requestId)
        } catch {
          guard registry.finish(requestId) else { return }
          try? await callback.onError(requestId: requestId, error: Errors.requestError(error))
        }
      }
      registry.attach(requestId, task: task)
    }

    func cancel(requestId: Int64) throws { registry.cancel(requestId) }

    func deleteAssets(handle: Int64, assetIds: [String]) async throws {
      try await translatingErrors {
        try await registry.analyzer(handle).deleteAssets(assetIds.map { .init($0) })
      }
    }

    func deleteAllAssets(handle: Int64) async throws {
      try await translatingErrors { try await registry.analyzer(handle).deleteAllAssets() }
    }

    func updateFaceGroups(handle: Int64) async throws {
      try await translatingErrors { try await registry.analyzer(handle).update() }
    }

    func allAssetIds(handle: Int64) async throws -> [String] {
      try await translatingErrors {
        try await Self.collect(registry.analyzer(handle).allAssetIDs) { $0.rawValue }
      }
    }

    func allEntityIds(handle: Int64) async throws -> [String] {
      try await translatingErrors {
        try await Self.collect(registry.analyzer(handle).allEntities) { $0.id.rawValue }
      }
    }

    func allFaces(handle: Int64) async throws -> [FaceMessage] {
      try await translatingErrors {
        try await Self.collect(registry.analyzer(handle).allFaces, Self.message)
      }
    }

    func allAssetIdsByEntity(handle: Int64) async throws -> [AssetGroupMessage] {
      try await translatingErrors {
        try await Self.collect(registry.analyzer(handle).allAssetIDsByEntityID, Self.message)
      }
    }

    func allFacesByEntity(handle: Int64) async throws -> [FaceGroupMessage] {
      try await translatingErrors {
        try await Self.collect(registry.analyzer(handle).allFacesByEntityID, Self.message)
      }
    }

    func facesWithIds(handle: Int64, faceIds: [String]) async throws -> [FaceMessage] {
      try await translatingErrors {
        let sequence = try registry.analyzer(handle).fetchFaces(faceIds.map { .init($0) })
        return try await Self.collect(sequence, Self.message)
      }
    }

    func facesForEntities(handle: Int64, entityIds: [String]) async throws -> [FaceGroupMessage] {
      try await translatingErrors {
        let sequence = try registry.analyzer(handle).fetchFaces(for: entityIds.map { .init($0) })
        return try await Self.collect(sequence, Self.message)
      }
    }

    func facesInAssets(handle: Int64, assetIds: [String]) async throws -> [FaceGroupMessage] {
      try await translatingErrors {
        let sequence = try registry.analyzer(handle).fetchFaces(in: assetIds.map { .init($0) })
        return try await Self.collect(sequence) {
          FaceGroupMessage(key: $0.assetID.rawValue, faces: $0.faces.map(Self.message))
        }
      }
    }

    func assetIdsForEntities(handle: Int64, entityIds: [String]) async throws
      -> [AssetGroupMessage]
    {
      try await translatingErrors {
        let sequence = try registry.analyzer(handle).fetchAssetIDs(for: entityIds.map { .init($0) })
        return try await Self.collect(sequence, Self.message)
      }
    }

    // MARK: - Video

    func analyzeVideo(asset: AssetMessage, highlights: Bool, keyFrame: Bool) async throws
      -> VideoAnalysisMessage
    {
      try await translatingErrors {
        guard highlights || keyFrame else {
          throw Errors.invalidArgument("Request highlights, a key frame, or both.")
        }
        let video = MediaIntelligenceVideoAsset(
          id: .init(try Self.assetID(asset)), kind: .url(try Self.fileURL(asset.path)))
        let analyzer = VideoAnalyzer.shared
        var result = VideoAnalysisMessage()
        if highlights && keyFrame {
          let (highlightResult, keyFrameResult) = try await analyzer.analyze(
            video, for: HighlightAnalysisRequest(), KeyFrameAnalysisRequest())
          Self.apply(highlightResult, to: &result)
          Self.apply(keyFrameResult, to: &result)
        } else if highlights {
          Self.apply(try await analyzer.analyze(video, for: HighlightAnalysisRequest()), to: &result)
        } else {
          Self.apply(try await analyzer.analyze(video, for: KeyFrameAnalysisRequest()), to: &result)
        }
        return result
      }
    }

    private static func apply(
      _ result: Result<HighlightAnalysisRequest.Result, any Error>, to message: inout VideoAnalysisMessage
    ) {
      switch result {
      case .success(let value):
        message.highlights = value.highlights.map(Self.message)
        message.highlightLevels = value.levels.map {
          HighlightLevelMessage(range: Self.message($0.timeRange), level: Double($0.level))
        }
      case .failure(let error):
        message.highlightError = Errors.requestError(error)
      }
    }

    private static func apply(
      _ result: Result<KeyFrameAnalysisRequest.Result, any Error>, to message: inout VideoAnalysisMessage
    ) {
      switch result {
      case .success(let value): message.keyFrameSeconds = value.timestamp.seconds
      case .failure(let error): message.keyFrameError = Errors.requestError(error)
      }
    }

    // MARK: - Handles

    func release(handle: Int64) async throws { registry.remove(handle) }

    func releaseAll() async throws -> Int64 { Int64(registry.removeAll()) }

    func liveHandleCount() throws -> Int64 { Int64(registry.count) }

    // MARK: - Conversions

    private static func collect<S: AsyncSequence, T>(_ sequence: S, _ transform: (S.Element) -> T)
      async throws -> [T]
    {
      var result: [T] = []
      for try await element in sequence { result.append(transform(element)) }
      return result
    }

    private static func message(_ face: FaceGroupAnalyzer.Face) -> FaceMessage {
      FaceMessage(
        id: face.id.rawValue, assetId: face.assetID.rawValue, entityId: face.entityID?.rawValue,
        x: face.bounds.origin.x, y: face.bounds.origin.y, width: face.bounds.width,
        height: face.bounds.height)
    }

    private static func message(
      _ group: (entityID: FaceGroupAnalyzer.Entity.ID, assetIDs: [MediaIntelligenceImageAsset.ID])
    ) -> AssetGroupMessage {
      AssetGroupMessage(entityId: group.entityID.rawValue, assetIds: group.assetIDs.map(\.rawValue))
    }

    private static func message(
      _ group: (entityID: FaceGroupAnalyzer.Entity.ID, faces: [FaceGroupAnalyzer.Face])
    ) -> FaceGroupMessage {
      FaceGroupMessage(key: group.entityID.rawValue, faces: group.faces.map(Self.message))
    }

    private static func message(_ range: CMTimeRange) -> TimeRangeMessage {
      TimeRangeMessage(startSeconds: range.start.seconds, durationSeconds: range.duration.seconds)
    }

    private static func assetID(_ asset: AssetMessage) throws -> String {
      guard !asset.id.isEmpty else { throw Errors.invalidArgument("Asset ids cannot be empty.") }
      return asset.id
    }

    /// Validates ids and files up front: a missing file otherwise fails the
    /// whole batch with an unspecific `faceGroupProcessing` error.
    private static func imageAssets(_ assets: [AssetMessage]) throws -> [MediaIntelligenceImageAsset] {
      guard !assets.isEmpty else { throw Errors.invalidArgument("Pass at least one asset.") }
      var seen = Set<String>()
      return try assets.map { asset in
        let id = try assetID(asset)
        guard seen.insert(id).inserted else {
          throw Errors.invalidArgument("Asset id '\(id)' appears more than once.")
        }
        return MediaIntelligenceImageAsset(id: .init(id), kind: .url(try fileURL(asset.path)))
      }
    }

    private static func fileURL(_ path: String) throws -> URL {
      let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw Errors.notFound("No file at '\(url.path)'.")
      }
      return url
    }

    private static func directoryURL(_ path: String) throws -> URL {
      guard !path.isEmpty else {
        throw Errors.invalidArgument("The working directory path cannot be empty.")
      }
      return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
  }
#endif

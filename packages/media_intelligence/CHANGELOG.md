## 0.1.0

* Initial release: MediaIntelligence bindings for iOS 27+ / macOS 27+ over
  Pigeon platform channels.
* `FaceGroupAnalyzer`: a persistent face library with streamed
  insert/update and identify results, regrouping into people, state, and
  every fetch, delete and purge operation.
* `VideoAnalyzer`: highlights with per-span levels, and key frames, each
  with its own success or error.
* Up-front validation of asset ids and files, typed errors, handle
  lifecycle with finalizers, and a testing library for fakes.
* Known limitation: the synthetic highlight fixture passes on macOS but
  returns no highlights on iOS 27; real-video highlights and real-face grouping
  still need device validation.

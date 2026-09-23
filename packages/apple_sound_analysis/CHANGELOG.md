## 0.1.0

* Initial release: SoundAnalysis bindings for iOS 15+ and macOS 12+ over
  Pigeon platform channels.
* Built-in and custom Core ML sound classifiers, model compilation/cache,
  label discovery and validated window/overlap configuration.
* Audio-file, pushed mono/stereo or multichannel PCM, and microphone analysis
  with typed window results, confidence scores and explicit cancellation.
* Callback routing registered before startup, ordered native event delivery,
  serialized PCM writes, and cancellation that waits for pending starts.
* Microphone authorization queries/requests, capture-buffer copying, and
  restoration of iOS audio-session category settings on stop.
* Injectable test bindings, unit and real-framework integration tests,
  a Material example, bundled speech/tone fixtures and a device test driver.

## 0.1.0

* Add public Dart wrappers for SpeechAnalyzer, transcribers, detector,
  SpeechRecognizer, model assets, authorization, typed results and errors.
* Support file, version 27 media-asset and microphone inputs, with a
  simulated live source for permission-free tests.
* Add buffered request streams, finalization, cancellation, global cleanup,
  injected test bindings and native request-count queries.
* Reserve native request IDs before preparation, preserve cancellation during
  startup, copy retained tap buffers, propagate conversion errors, and restore
  iOS audio-session category/mode/options after capture.
* Add an example with sample transcription, word timing, explicit permissions
  and downloads, plus unit, widget and real-framework integration tests.
* Document availability, Apple's asset-status behavior, detector limitations,
  unbridged APIs and checks still requiring manual verification.

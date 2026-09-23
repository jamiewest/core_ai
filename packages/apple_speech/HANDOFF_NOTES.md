# apple_speech handoff notes

Status: IN PROGRESS (first version, written mid-implementation).

## Done so far
- Pigeon schema `pigeons/apple_speech_api.dart` (generated Dart + Swift).
- Swift (darwin/apple_speech/Sources/apple_speech/): Errors, Requests
  (registry, EventPump, Mutex), Authorization, AudioCapture (mic via
  AVAudioEngine, SimulatedMicrophone, BufferConverter), Modules (build +
  validation + result conversion), Analysis (SpeechAnalyzer runs), Assets
  (AssetInventory install with progress polling), Recognition
  (SFSpeechRecognizer), AppleSpeechHostApiImpl, AppleSpeechPlugin.
  `flutter build macos --debug` in example/ compiles cleanly (pod target
  macOS 12).
- Dart: lib/src/errors.dart, bindings.dart, common.dart.

## Still to do
- Dart: request base (streams/cancel), modules, analyzer, assets,
  recognizer, speech.dart, public exports, testing.dart.
- Unit tests, integration tests, example app, assets, Info.plist keys and
  entitlements, README, CHANGELOG, iOS build, test_driver.

## Framework facts found by probing (macOS 27, CLI)
- SpeechAnalyzer/SpeechTranscriber work WITHOUT speech authorization.
- Volatile results are one run spanning the whole range; final results
  carry per-word audioTimeRange + transcriptionConfidence runs.
- Unsupported or not-installed locale -> SFSpeechErrorDomain code 3
  "Audio format is not supported" (misleading); the plugin pre-checks.
- SpeechDetector alone: bestAvailableAudioFormat is 0 ch/0 Hz and the
  analyzer traps; with a transcriber it runs but produced no results.
- AssetInventory.status is `supported` (not `installed`) for
  DictationTranscriber and transcriber+detector even though they run.
- SFSpeechError raw codes: 3 unexpectedAudioFormat, 4 noModel, 5
  incompatibleAudioFormats, 9 moduleOutputFailed, 10
  assetLocaleNotAllocated, 11 tooManyAssetLocalesAllocated, 15
  cannotAllocateUnsupportedLocale, 16 insufficientResources, 17
  audioDisordered, 18 cannotConfigureAudioSystem.

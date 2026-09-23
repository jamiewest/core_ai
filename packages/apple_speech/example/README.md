# Speech example

A Material 3 app with light/dark themes. Select SpeechTranscriber,
DictationTranscriber or the legacy recognizer, transcribe a bundled English
sample, read it as a media asset (27+), or choose Listen and Stop and finalize.
The app displays final/partial text, word timing and available confidence.

Missing models disable transcription and expose an explicit download action.
Startup never prompts for permission or downloads models. Listen requests
microphone permission; choosing legacy recognition requests speech permission
when transcription starts. The legacy demo requires on-device recognition.
The app includes the required usage descriptions, macOS audio-input and
network-client entitlements.

```sh
flutter run -d macos
```

The sample contains: “The quick brown fox jumps over the lazy dog. Today is a
beautiful day for a walk in the park.” It is synthesized locally with macOS
Samantha, not a recording of a person. Recreate it with:

```sh
say -v Samantha -r 145 -o /tmp/speech_sample.aiff \
  'The quick brown fox jumps over the lazy dog. Today is a beautiful day for a walk in the park.'
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/speech_sample.aiff assets/speech.wav
```

It is a small mono 16 kHz PCM WAV. The app extracts it to its own temporary
directory and deletes that copy after the screen and active work are disposed.

## Checks

From the package directory:

```sh
flutter test test
flutter test example/test
```

From this example directory, run each integration file separately:

```sh
flutter test integration_test/apple_speech_test.dart -d macos
flutter test integration_test/app_test.dart -d macos
flutter build ios --no-codesign --debug
```

The framework suite expects macOS 27 with English (US) SpeechTranscriber and
DictationTranscriber models installed. It fails with an explanatory setup
assertion if the prerequisite is missing; it does not silently download models
or skip transcription. It checks exact normalized words, timing, UTF-16 ranges,
confidence, file/asset/simulated-live sources, validation and request cleanup.
The app integration test verifies real sample output, timing UI, and zero
active native requests. Neither suite records the microphone or requests
permissions. The legacy test verifies an explicit authorization error when
access has not been granted, rather than opening a permission prompt.

For an unlocked iPhone with models installed, the provided driver can be used:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_speech_test.dart -d YOUR_DEVICE_ID
```

An iOS build pass alone does not verify device runtime. Manually exercise
Listen/Stop, denied permissions, legacy authorization and asset downloads when
those checks are wanted.

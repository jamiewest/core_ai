# media_intelligence

Flutter bindings for Apple's **MediaIntelligence** framework (iOS 27 /
macOS 27), built on [Pigeon](https://pub.dev/packages/pigeon) platform
channels.

It covers two things: grouping the faces in a photo library into people,
and finding the highlights and key frame of a video. Both run on the device.

```dart
import 'package:media_intelligence/media_intelligence.dart';

final video = await VideoAnalyzer.analyze(
  const MediaAsset(id: 'trip', path: '/path/trip.mov'),
);
video.highlights?.highlights; // the spans worth showing
video.keyFrame;               // a good thumbnail time

final faces = await FaceGroupAnalyzer.open('$appSupport/faces');
await faces.insertOrUpdate(photos).drain<void>();
await faces.update();
final people = await faces.assetIdsByEntity(); // person → photo ids
await faces.dispose();
```

## Requirements

| | |
|---|---|
| Everything | iOS 27+ / macOS 27+ |
| Builds for | iOS 15+ and macOS 12+ |
| Toolchain | Xcode 27, Flutter 3.38+ |

On older systems `MediaIntelligence.isSupported()` returns false, and calls
throw `MediaIntelligenceErrorCode.unsupported`.

The framework reads files. For Photos library items, export them to files
first; this package has no Photos integration.

**Tested on macOS 27:**
- 14 unit tests pass.
- 10 integration tests pass against the real framework. They cover video
  highlights, levels and key frames on a generated two-scene clip, and the
  whole face-library lifecycle.
- The example app test passes.
- The iOS example builds.

**Not tested:** grouping real faces into people. There are no photos of
people in this repository. The integration suite has a test for your own
photos, which is skipped unless you pass
`--dart-define=MEDIA_INTELLIGENCE_FACE_DIR=<folder of photos of people>`.
Runs on an iPhone are also untested.

## Video

`VideoAnalyzer.analyze` runs highlight analysis, key frame analysis, or both.
Both in one call is cheaper than two calls. Each analysis succeeds or fails
on its own, so check `highlightsError` and `keyFrameError`.

* `highlights.highlights`: the spans worth showing.
* `highlights.levels`: a score for each span, covering the whole video in
  order.
* `keyFrame`: the time of the most representative frame.

The first analysis in a process is slow while models load: about 20 s for
the 6 s test clip, then about 1–2 s after that.

## Face groups

`FaceGroupAnalyzer` keeps a face library in a working directory you choose.
The library persists; open the same directory again on the next launch.

1. `insertOrUpdate(assets)` adds images, or re-analyzes ids already present.
   It streams the faces found in each asset. Work starts when you listen.
2. `update()` regroups faces into people ("entities"). `state()` reports
   `stale` when assets changed since the last update.
3. Query the results:
   - `entityIds()`, `faces()`, `facesWithIds(...)`;
   - `assetIdsByEntity()`, `facesByEntity()`;
   - `assetIdsForEntities(...)`, `facesForEntities(...)`, `facesInAssets(...)`.
4. `identifyFaces(assets)` matches faces in new images against known people
   without adding the images.
5. Remove assets with `deleteAssets(ids)` and `deleteAllAssets()`. Delete the
   whole library with `FaceGroupAnalyzer.purge(directory)`.

Asset ids are yours: use a stable key such as a database id. Ids in one
call must be unique, and every file must exist. This package checks both
before calling the framework, whose own error for a missing file is
unspecific.

`Face.bounds` is the `CGRect` Apple reports, passed through unchanged. Its
coordinate space isn't documented, and this package couldn't observe it
without photos of people.

## Swift → Dart

| MediaIntelligence (Swift) | media_intelligence (Dart) |
|---|---|
| `MediaIntelligenceImageAsset`, `MediaIntelligenceVideoAsset` (`.url`) | `MediaAsset` |
| `FaceGroupAnalyzer(workingDirectory:)`, `purge` | `FaceGroupAnalyzer.open`, `FaceGroupAnalyzer.purge` |
| `insertOrUpdateAssets`, `identifyFaces` | `insertOrUpdate`, `identifyFaces` (Streams) |
| `update`, `state` | `update()`, `state()` |
| `allEntities`, `allAssetIDs`, `allFaces` | `entityIds()`, `assetIds()`, `faces()` |
| `allAssetIDsByEntityID`, `allFacesByEntityID` | `assetIdsByEntity()`, `facesByEntity()` |
| `fetchFaces(_:)`, `fetchFaces(for:)`, `fetchFaces(in:)`, `fetchAssetIDs(for:)` | `facesWithIds`, `facesForEntities`, `facesInAssets`, `assetIdsForEntities` |
| `deleteAssets`, `deleteAllAssets` | `deleteAssets`, `deleteAllAssets` |
| `VideoAnalyzer.shared.analyze(_:for:)` | `VideoAnalyzer.analyze` |
| `HighlightAnalysisRequest.Result`, `KeyFrameAnalysisRequest.Result` | `HighlightAnalysis`, `VideoAnalysis.keyFrame` |
| `MediaIntelligenceError` | `MediaIntelligenceException` |

## Not bridged

* Progress for `update(subprogress:)`. `update()` only reports completion.

## Known platform behavior

Observed on macOS 27:

* Video analysis can't be cancelled. Cancelling the Swift task doesn't stop
  it.
* A file that isn't a readable video fails each analysis in the result
  (NSOSStatusErrorDomain -18, "Analysis failed to complete"). It doesn't
  throw.
* An image without faces is processed, but isn't listed by `assetIds()`.
* A file that isn't an image, such as a video, fails the whole
  `insertOrUpdate` call with `faceGroupProcessing`.
* Cancelling an `insertOrUpdate` subscription stops the events. The framework
  may still finish storing the assets.
* `purge` on a directory that was never opened throws `workingDirectory`.
  After a purge the directory itself remains.
* The framework prints progress lines ("Processed asset …") to standard
  output.

## Errors

Every failure is a `MediaIntelligenceException` with a
`MediaIntelligenceErrorCode`:
- `unsupported`, `invalidArgument`, `invalidHandle`, `notFound`;
- `workingDirectory`, `mediaProcessing`, `faceGroupProcessing` and
  `resultFetching`, which are Apple's `MediaIntelligenceError` cases;
- `mediaIntelligenceError`, `unknown`.

## Resources

Call `dispose()` on a `FaceGroupAnalyzer`; the library stays on disk. A
`Finalizer` releases forgotten analyzers eventually. After a hot restart,
call `MediaIntelligence.releaseAll()`. `MediaIntelligence.liveHandleCount()`
helps check for leaks.

## Development

```sh
dart run pigeon --input pigeons/media_intelligence_api.dart
flutter test
cd example
flutter test integration_test/media_intelligence_test.dart -d macos
flutter test integration_test/app_test.dart -d macos

# Regenerate the sample clip and image:
swiftc -O ../tool/make_assets.swift -o /tmp/make_assets && /tmp/make_assets assets

# On a physical device (wireless debugging needs flutter drive):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/media_intelligence_test.dart -d <device id> \
  --publish-port
```

Run integration test files one at a time on macOS.
`package:media_intelligence/testing.dart` lets you replace
`MediaIntelligenceBindings.instance` with fakes.

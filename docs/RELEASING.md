# Releasing the Apple AI plugins

The repository contains ten independently published Flutter plugins. The root
`apple_ai_workspace` is private (`publish_to: none`); `core_ai` wraps only
Apple's Core AI framework and does not re-export the other plugins.

All packages start at `0.1.0` and use the MIT license, copyright Jamie West.
The Vision package is named `apple_vision_native`: `apple_vision` belongs to
another publisher. Package-name checks are provisional until publication.

## Prepare a release

1. Update the package's `pubspec.yaml` version and matching Darwin `.podspec`
   version. Other packages keep their versions unless they also need a release.
2. Add a matching `## <version>` entry to its `CHANGELOG.md`, describing the
   changes a consumer needs to know. The existing `0.1.0` entries describe the
   initial API. Review OS requirements and known limitations in the README.
3. Run `bash tool/check_release.sh` from the repository root. To limit tests and
   publication checks, pass package names, for example:

   ```sh
   bash tool/check_release.sh apple_vision_native foundation_models
   ```

   The script resolves the workspace, checks analysis and formatting, runs unit
   and available example widget tests, and runs `flutter pub publish --dry-run`.
   It never uploads a package. Review each dry-run file list and all warnings.
   Package `.pubignore` files omit internal handoff notes and example Pod locks
   while retaining source, native manifests, tests, and example assets.
4. For changed native code or package identities, run the affected example's
   framework and app integration tests on macOS, one file per command, and
   build the iOS example. For Vision:

   ```sh
   cd packages/apple_vision_native/example
   flutter test integration_test/apple_vision_native_test.dart -d macos
   flutter build ios --no-codesign --debug
   ```

   Run physical-device integration tests for affected device behavior. Existing
   hardware results and remaining limitations are recorded in
   [HANDOFF.md](HANDOFF.md). In particular, Media Intelligence's iOS highlight
   fixture still fails, and real-face grouping requires manual verification;
   do not describe those paths as device-verified.
5. Commit the reviewed release and push it to
   <https://github.com/jamiewest/core_ai> so the published repository links
   resolve, including the renamed Vision directory. Rerun the dry-run on the
   committed release to eliminate uncommitted-file warnings.

## Publish an individual package

Publishing is a separate, explicit step after validation. Sign in with the
Google account that should own the packages when pub requests authentication.
These packages have no dependencies on each other, so there is no required
publication order.

```sh
cd packages/apple_vision_native
flutter pub publish
```

Review the archive and confirm the upload interactively. Repeat for each
package being released. After a successful upload, create and push a tag such
as `apple_vision_native-v0.1.0` at the release commit. Use the same
`<package>-v<version>` convention for subsequent independent releases.

The workspace `resolution: workspace` setting is for local development; pub
supports publishing workspace members. Do not add sibling path dependencies
to published plugin manifests.

For pub's publication rules and account setup, see the official
[publishing guide](https://dart.dev/tools/pub/publishing) and
[workspace documentation](https://dart.dev/tools/pub/workspaces).

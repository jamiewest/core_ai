## 0.1.0

* First publication as `apple_vision_native` (renamed from the unpublished
  workspace package `apple_vision`).

* Initial release: 25 modern Vision requests over Pigeon platform channels,
  available on iOS 27+ and macOS 27+ with older deployment targets supported.
* Text and document recognition, barcodes, faces, people and animal poses,
  classification, aesthetics, lens smudges, saliency, segmentation, rectangles,
  horizon, contours and image feature prints.
* File, Flutter asset, encoded image and BGRA pixel inputs; batch requests
  share one decoded image and preserve errors for individual requests.
* Normalized geometry with conversion to Flutter coordinates, raw masks with
  row stride and PNG encoding, and feature-print distance comparisons.
* Injectable bindings, typed errors, a Material example, Dart unit tests and
  integration tests against bundled images.

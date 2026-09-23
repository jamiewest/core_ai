import CoreImage
import CoreVideo
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Converts between `CVPixelBuffer` and `PixelBufferMessage`, and to and from
/// encoded images.
enum PixelBufferBridge {
  /// IOSurface-backed and Metal-compatible, so Core ML can hand buffers to the
  /// GPU and Neural Engine without copying.
  private static let attributes: CFDictionary =
    [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferMetalCompatibilityKey: true,
    ] as CFDictionary

  /// No colour management: pixel values pass through unchanged, which is what
  /// models trained on raw sRGB bytes expect.
  private static let context = CIContext(options: [
    .workingColorSpace: NSNull(),
    .outputColorSpace: NSNull(),
    .cacheIntermediates: false,
  ])

  static func create(width: Int, height: Int, pixelFormatType: OSType) throws -> CVPixelBuffer {
    guard width > 0, height > 0 else {
      throw Errors.invalidArgument(
        "Pixel buffer size must be positive, got \(width)x\(height).")
    }
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, pixelFormatType, attributes, &buffer)
    guard status == kCVReturnSuccess, let buffer else {
      throw CoreMLPigeonError(
        .pixelBufferError,
        "CVPixelBufferCreate failed (\(status)) for \(width)x\(height) "
          + "format \(fourCharCode(pixelFormatType)).")
    }
    zero(buffer)
    return buffer
  }

  static func make(_ message: PixelBufferMessage) throws -> CVPixelBuffer {
    let buffer = try create(
      width: Int(message.width),
      height: Int(message.height),
      pixelFormatType: OSType(truncatingIfNeeded: message.pixelFormatType))
    try write(message, into: buffer)
    return buffer
  }

  /// Copies the message's planes into [buffer] row by row, tolerating
  /// different row strides on each side.
  static func write(_ message: PixelBufferMessage, into buffer: CVPixelBuffer) throws {
    let planes = planeLayouts(buffer)
    guard message.planes.count == planes.count else {
      throw Errors.invalidArgument(
        "Pixel format \(fourCharCode(CVPixelBufferGetPixelFormatType(buffer))) has "
          + "\(planes.count) plane(s), got \(message.planes.count).")
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    for (layout, plane) in zip(planes, message.planes) {
      guard let base = layout.baseAddress(buffer) else { continue }
      let sourceRowBytes = Int(plane.bytesPerRow)
      let rows = min(layout.height, Int(plane.height))
      let rowBytes = min(sourceRowBytes, layout.bytesPerRow)
      guard plane.data.data.count >= sourceRowBytes * rows else {
        throw Errors.invalidArgument(
          "Plane data has \(plane.data.data.count) bytes; \(rows) rows of "
            + "\(sourceRowBytes) bytes are required.")
      }
      plane.data.data.withUnsafeBytes { source in
        for row in 0..<rows {
          (base + row * layout.bytesPerRow).copyMemory(
            from: source.baseAddress! + row * sourceRowBytes, byteCount: rowBytes)
        }
      }
    }
  }

  static func message(_ buffer: CVPixelBuffer) -> PixelBufferMessage {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let planes = planeLayouts(buffer).map { layout in
      let count = layout.bytesPerRow * layout.height
      let data = layout.baseAddress(buffer).map { Data(bytes: $0, count: count) } ?? Data()
      return PixelBufferPlaneMessage(
        width: Int64(layout.width),
        height: Int64(layout.height),
        bytesPerRow: Int64(layout.bytesPerRow),
        data: FlutterStandardTypedData(bytes: data))
    }
    return PixelBufferMessage(
      width: Int64(CVPixelBufferGetWidth(buffer)),
      height: Int64(CVPixelBufferGetHeight(buffer)),
      pixelFormatType: Int64(CVPixelBufferGetPixelFormatType(buffer)),
      planes: planes)
  }

  static func zero(_ buffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    for layout in planeLayouts(buffer) {
      if let base = layout.baseAddress(buffer) {
        memset(base, 0, layout.bytesPerRow * layout.height)
      }
    }
  }

  // MARK: Encoded images

  /// Decodes [encoded], resizes it to [width] x [height] (keeping its own size
  /// when null) and renders it into a new pixel buffer of [pixelFormatType].
  ///
  /// The image is stretched, not letterboxed: Core ML's own crop-and-scale
  /// options need Vision, which this plugin does not depend on.
  static func fromEncodedImage(
    _ encoded: Data, pixelFormatType: OSType, width: Int?, height: Int?
  ) throws -> CVPixelBuffer {
    guard var image = CIImage(data: encoded, options: [.applyOrientationProperty: true]) else {
      throw Errors.invalidArgument("Could not decode the image data.")
    }
    image = image.transformed(
      by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    let targetWidth = width ?? Int(image.extent.width.rounded())
    let targetHeight = height ?? Int(image.extent.height.rounded())
    if targetWidth != Int(image.extent.width) || targetHeight != Int(image.extent.height) {
      image = image.samplingLinear().transformed(
        by: CGAffineTransform(
          scaleX: CGFloat(targetWidth) / image.extent.width,
          y: CGFloat(targetHeight) / image.extent.height))
    }
    let buffer = try create(
      width: targetWidth, height: targetHeight, pixelFormatType: pixelFormatType)
    context.render(
      image, to: buffer,
      bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
      colorSpace: nil)
    return buffer
  }

  static func encode(_ buffer: CVPixelBuffer, as encoding: ImageEncodingMessage, quality: Double)
    throws -> Data
  {
    let image = CIImage(cvPixelBuffer: buffer)
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let data: Data?
    switch encoding {
    case .png:
      data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: sRGB)
    case .jpeg:
      data = context.jpegRepresentation(
        of: image, colorSpace: sRGB,
        options: [
          CIImageRepresentationOption(
            rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
        ])
    }
    guard let data else {
      throw CoreMLPigeonError(
        .pixelBufferError,
        "Core Image cannot encode pixel format "
          + "\(fourCharCode(CVPixelBufferGetPixelFormatType(buffer))) as \(encoding).")
    }
    return data
  }

  // MARK: Helpers

  private struct PlaneLayout {
    let index: Int?
    let width: Int
    let height: Int
    let bytesPerRow: Int

    func baseAddress(_ buffer: CVPixelBuffer) -> UnsafeMutableRawPointer? {
      guard let index else { return CVPixelBufferGetBaseAddress(buffer) }
      return CVPixelBufferGetBaseAddressOfPlane(buffer, index)
    }
  }

  private static func planeLayouts(_ buffer: CVPixelBuffer) -> [PlaneLayout] {
    let count = CVPixelBufferGetPlaneCount(buffer)
    guard count > 0 else {
      return [
        PlaneLayout(
          index: nil,
          width: CVPixelBufferGetWidth(buffer),
          height: CVPixelBufferGetHeight(buffer),
          bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
      ]
    }
    return (0..<count).map { plane in
      PlaneLayout(
        index: plane,
        width: CVPixelBufferGetWidthOfPlane(buffer, plane),
        height: CVPixelBufferGetHeightOfPlane(buffer, plane),
        bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, plane))
    }
  }

  static func fourCharCode(_ code: OSType) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "\(code)" }
    return "'\(String(decoding: bytes, as: UTF8.self))'"
  }
}

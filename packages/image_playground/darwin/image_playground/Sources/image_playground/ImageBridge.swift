import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// Decoding and file access run on the generic executor, away from UI work.
enum ImageBridge {
  static let maxBytes = 64 * 1024 * 1024
  static let maxPixels = 64 * 1024 * 1024

  static func decode(_ message: ImageInputMessage) throws -> CGImage {
    if message.kind == .pixels {
      guard let width = message.width, let height = message.height,
        width > 0, height > 0, width <= 16384, height <= 16384,
        width <= Int64(maxPixels) / height,
        let bytes = message.bytes?.data, bytes.count <= maxBytes
      else { throw Errors.invalid("Invalid BGRA dimensions or data (maximum 64 MiB).") }
      let stride = message.bytesPerRow ?? width * 4
      guard stride >= width * 4, stride <= Int64(bytes.count) / height,
        let provider = CGDataProvider(data: bytes as CFData),
        let image = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8,
          bitsPerPixel: 32, bytesPerRow: Int(stride), space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
      else { throw Errors.invalid("BGRA data must contain height rows of bytesPerRow bytes.") }
      return image
    }
    let data: Data
    switch message.kind {
    case .file:
      guard let path = message.path, !path.isEmpty else { throw Errors.invalid("A file path is required.") }
      data = try read(URL(fileURLWithPath: path))
    case .encoded:
      guard let bytes = message.bytes?.data, !bytes.isEmpty, bytes.count <= maxBytes
      else { throw Errors.invalid("Encoded images need 1–64 MiB of data.") }
      data = bytes
    case .pixels: fatalError("Handled above")
    }
    return try decode(data)
  }

  static func read(_ url: URL) throws -> Data {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw ImagePlaygroundPigeonError("not_found", "No image at \(url.path).")
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber, size.int64Value <= maxBytes else {
      throw Errors.invalid("Image files may not exceed 64 MiB.")
    }
    return try Data(contentsOf: url, options: .mappedIfSafe)
  }

  static func decode(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 16384, height <= 16384, width <= maxPixels / height,
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
      ] as CFDictionary)
    else { throw ImagePlaygroundPigeonError("image_error", "The image is invalid or exceeds 64 megapixels / 16384 pixels per edge.") }
    return image
  }

  static func result(url: URL) async throws -> ResultMessage {
    let data = try read(url)
    let image = try decode(data)
    // Normalize orientation and encode a portable Flutter-decodable PNG.
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
    else { throw ImagePlaygroundPigeonError("image_error", "Could not create PNG encoder.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw ImagePlaygroundPigeonError("image_error", "Could not encode the generated image.")
    }
    return ResultMessage(bytes: FlutterStandardTypedData(bytes: output as Data), typeIdentifier: UTType.png.identifier,
      width: Int64(image.width), height: Int64(image.height))
  }

  static func glyph(data: Data, identifier: String, description: String) async throws -> ResultMessage {
    let image = try decode(data)
    return ResultMessage(bytes: FlutterStandardTypedData(bytes: data), typeIdentifier: "com.apple.emoji.sticker",
      width: Int64(image.width), height: Int64(image.height), contentIdentifier: identifier, contentDescription: description)
  }
}

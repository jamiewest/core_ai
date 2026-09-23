import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers
#endif

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Core Video pixel formats masks come back in.
enum MaskPixelFormat {
  /// `kCVPixelFormatType_OneComponent8`.
  static let oneComponent8: OSType = 0x4C30_3038
  /// `kCVPixelFormatType_OneComponent16Half`.
  static let oneComponent16Half: OSType = 0x4C30_3068
  /// `kCVPixelFormatType_OneComponent32Float`.
  static let oneComponent32Float: OSType = 0x4C30_3066

  static func describe(_ type: OSType) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((type >> $0) & 0xFF) }
    if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }),
      let text = String(bytes: bytes, encoding: .ascii)
    {
      return text
    }
    return "0x" + String(type, radix: 16)
  }
}

/// Decodes `ImageInputMessage`s, and converts mask pixel buffers to and from
/// the wire format.
enum ImageBridge {
  // MARK: - Input

  /// Decodes an image input into a `CGImage`.
  static func cgImage(_ message: ImageInputMessage) throws -> CGImage {
    switch message.kind {
    case .file:
      guard let path = message.path, !path.isEmpty else {
        throw Errors.invalidArgument("A file image needs a path.")
      }
      let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw Errors.notFound("No image file at '\(url.path)'.")
      }
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw Errors.image("Could not decode the image at '\(url.path)'.")
      }
      return image
    case .encoded:
      guard let data = message.bytes?.data, !data.isEmpty else {
        throw Errors.invalidArgument("An encoded image needs bytes.")
      }
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        throw Errors.image("Could not decode \(data.count) bytes of image data.")
      }
      return image
    case .pixels:
      guard let data = message.bytes?.data, let width = message.width,
        let height = message.height
      else {
        throw Errors.invalidArgument("A pixel image needs bytes, width and height.")
      }
      guard width > 0, height > 0 else {
        throw Errors.invalidArgument("Image size must be positive, got \(width)x\(height).")
      }
      let bytesPerRow = Int(message.bytesPerRow ?? Int64(width * 4))
      guard bytesPerRow >= Int(width) * 4 else {
        throw Errors.invalidArgument(
          "bytesPerRow \(bytesPerRow) is smaller than \(width) BGRA pixels.")
      }
      guard data.count >= bytesPerRow * Int(height) else {
        throw Errors.invalidArgument(
          "Pixel data has \(data.count) bytes; \(height) rows of \(bytesPerRow) "
            + "bytes are required.")
      }
      guard let provider = CGDataProvider(data: data as CFData),
        let image = CGImage(
          width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32,
          bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
              | CGBitmapInfo.byteOrder32Little.rawValue),
          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
      else {
        throw Errors.image("Could not build an image from \(width)x\(height) BGRA pixels.")
      }
      return image
    }
  }

  /// `CGImagePropertyOrientation`'s raw value for a message.
  static func orientation(_ message: ImageOrientationMessage?) -> CGImagePropertyOrientation? {
    guard let message else { return nil }
    switch message {
    case .up: return .up
    case .upMirrored: return .upMirrored
    case .down: return .down
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .right: return .right
    case .rightMirrored: return .rightMirrored
    case .left: return .left
    }
  }

  /// The size of [image] once [orientation] has been applied. Orientations
  /// that rotate by 90 degrees swap width and height.
  static func size(
    of image: CGImage, orientation: CGImagePropertyOrientation?
  ) -> ImageSizeMessage {
    let rotated: Bool
    switch orientation {
    case .leftMirrored, .right, .rightMirrored, .left: rotated = true
    default: rotated = false
    }
    return ImageSizeMessage(
      width: Int64(rotated ? image.height : image.width),
      height: Int64(rotated ? image.width : image.height))
  }

  // MARK: - Masks

  /// Copies a mask pixel buffer into the wire format.
  static func mask(_ buffer: CVPixelBuffer) throws -> MaskImageMessage {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let planar = CVPixelBufferIsPlanar(buffer)
    let bytesPerRow =
      planar
      ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
    let base =
      planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer)
    guard let base else {
      throw Errors.mask("The mask's pixel buffer has no base address.")
    }
    return MaskImageMessage(
      width: Int64(width),
      height: Int64(height),
      bytesPerRow: Int64(bytesPerRow),
      pixelFormatType: Int64(Int32(bitPattern: CVPixelBufferGetPixelFormatType(buffer))),
      bytes: FlutterStandardTypedData(bytes: Data(bytes: base, count: bytesPerRow * height)))
  }

  /// Encodes a mask as a grayscale PNG.
  ///
  /// Float masks are clamped to `0...1` and scaled to 8 bits.
  static func png(_ mask: MaskImageMessage) throws -> Data {
    let width = Int(mask.width)
    let height = Int(mask.height)
    let bytesPerRow = Int(mask.bytesPerRow)
    guard width > 0, height > 0 else {
      throw Errors.invalidArgument("Mask size must be positive, got \(width)x\(height).")
    }
    let source = mask.bytes.data
    guard source.count >= bytesPerRow * height else {
      throw Errors.invalidArgument(
        "Mask data has \(source.count) bytes; \(height) rows of \(bytesPerRow) "
          + "bytes are required.")
    }
    let format = OSType(bitPattern: Int32(truncatingIfNeeded: mask.pixelFormatType))
    var gray = Data(count: width * height)
    gray.withUnsafeMutableBytes { output in
      let out = output.bindMemory(to: UInt8.self)
      source.withUnsafeBytes { input in
        let raw = input.baseAddress!
        for row in 0..<height {
          let rowStart = raw + row * bytesPerRow
          for column in 0..<width {
            let value: Float
            switch format {
            case MaskPixelFormat.oneComponent32Float:
              value = rowStart.loadUnaligned(fromByteOffset: column * 4, as: Float.self)
            case MaskPixelFormat.oneComponent16Half:
              value = Float(rowStart.loadUnaligned(fromByteOffset: column * 2, as: Float16.self))
            default:
              value =
                Float(rowStart.loadUnaligned(fromByteOffset: column, as: UInt8.self)) / 255
            }
            out[row * width + column] = UInt8(max(0, min(1, value)) * 255)
          }
        }
      }
    }
    guard let provider = CGDataProvider(data: gray as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else {
      throw Errors.mask(
        "Could not build a \(width)x\(height) grayscale image from a "
          + "\(MaskPixelFormat.describe(format)) mask.")
    }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData, pngType, 1, nil)
    else {
      throw Errors.mask("Could not create a PNG encoder.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw Errors.mask("Could not encode the mask as a PNG.")
    }
    return output as Data
  }

  private static var pngType: CFString {
    #if canImport(UniformTypeIdentifiers)
      if #available(iOS 14.0, macOS 11.0, *) { return UTType.png.identifier as CFString }
    #endif
    return "public.png" as CFString
  }
}

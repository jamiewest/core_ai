// Renders the deterministic images the integration tests analyze.
//
// Run from the package root:
//   swift tool/make_assets.swift example/assets
//
// Everything is drawn with Core Graphics and Core Image, so the output is
// byte-for-byte reproducible on any Mac and needs no bundled binaries.

import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(
  fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "example/assets")
try FileManager.default.createDirectory(
  at: outputDirectory, withIntermediateDirectories: true)

func context(width: Int, height: Int) -> CGContext {
  CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
      | CGBitmapInfo.byteOrder32Little.rawValue)!
}

func gray(_ value: CGFloat) -> CGColor {
  CGColor(red: value, green: value, blue: value, alpha: 1)
}

/// Draws one line of Helvetica-Bold text with its baseline at (x, y), in
/// Core Graphics' lower-left origin space.
func draw(_ text: String, in ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat) {
  let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
  let attributed = NSAttributedString(
    string: text,
    attributes: [.font: font, .foregroundColor: gray(0)] as [NSAttributedString.Key: Any])
  ctx.textPosition = CGPoint(x: x, y: y)
  CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
}

func write(_ image: CGImage, to name: String) throws {
  let url = outputDirectory.appendingPathComponent(name)
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    fatalError("Could not create a PNG encoder for \(name).")
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write \(name).")
  }
  let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
  print("wrote \(name) (\(image.width)x\(image.height), \(size) bytes)")
}

// --- ocr_text.png: three lines of unambiguous words on white ----------------
do {
  let ctx = context(width: 900, height: 420)
  ctx.setFillColor(gray(1))
  ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 420))
  draw("HELLO VISION", in: ctx, x: 60, y: 300, size: 76)
  draw("FLUTTER PLUGIN", in: ctx, x: 60, y: 190, size: 76)
  draw("APPLE SILICON", in: ctx, x: 60, y: 80, size: 76)
  try write(ctx.makeImage()!, to: "ocr_text.png")
}

// --- qr_code.png: a QR code with a quiet zone, on white ---------------------
do {
  let payload = "apple_vision:qr-payload-42"
  let generator = CIFilter(name: "CIQRCodeGenerator")!
  generator.setValue(payload.data(using: .ascii), forKey: "inputMessage")
  generator.setValue("H", forKey: "inputCorrectionLevel")
  // CIQRCodeGenerator emits about 30 pixels across; scale it up so Vision has
  // enough modules to lock onto.
  let scaled = generator.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
  let code = CIContext().createCGImage(scaled, from: scaled.extent)!
  let margin = 48
  let ctx = context(width: code.width + margin * 2, height: code.height + margin * 2)
  ctx.setFillColor(gray(1))
  ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
  ctx.draw(
    code,
    in: CGRect(x: margin, y: margin, width: code.width, height: code.height))
  try write(ctx.makeImage()!, to: "qr_code.png")
}

// --- shapes.png: one dark rectangle on white -------------------------------
do {
  let ctx = context(width: 800, height: 600)
  ctx.setFillColor(gray(1))
  ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
  ctx.setFillColor(gray(0.05))
  ctx.fill(CGRect(x: 120, y: 90, width: 560, height: 420))
  try write(ctx.makeImage()!, to: "shapes.png")
}

// --- shapes_moved.png: the same rectangle, shifted, for feature prints ------
do {
  let ctx = context(width: 800, height: 600)
  ctx.setFillColor(gray(1))
  ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
  ctx.setFillColor(gray(0.05))
  ctx.fillEllipse(in: CGRect(x: 200, y: 150, width: 400, height: 300))
  try write(ctx.makeImage()!, to: "shapes_circle.png")
}

// --- document.png: a white page on a dark background ------------------------
do {
  let ctx = context(width: 1000, height: 760)
  ctx.setFillColor(gray(0.12))
  ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 760))
  ctx.setFillColor(gray(1))
  ctx.fill(CGRect(x: 130, y: 90, width: 740, height: 580))
  draw("INVOICE 2026", in: ctx, x: 180, y: 570, size: 54)
  draw("Item one  10.00", in: ctx, x: 180, y: 460, size: 38)
  draw("Item two  25.50", in: ctx, x: 180, y: 390, size: 38)
  draw("Total     35.50", in: ctx, x: 180, y: 300, size: 38)
  try write(ctx.makeImage()!, to: "document.png")
}

print("done")

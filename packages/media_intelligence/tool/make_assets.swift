// Generates the example/test assets:
//   swiftc -O tool/make_assets.swift -o /tmp/make_assets && /tmp/make_assets example/assets
// clip.mp4: 6 s, 30 fps, 320x240. A yellow circle crosses a blue scene, then
// a cut to a red scene with white squares.
// scene.png: 640x480 shapes with no faces.
import AVFoundation
import CoreGraphics
import CoreVideo

let dir = CommandLine.arguments[1]
let url = URL(fileURLWithPath: "\(dir)/clip.mp4")
try? FileManager.default.removeItem(at: url)
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let w = 320, h = 240, fps: Int32 = 30, frames = 180
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
for i in 0..<frames {
  while !input.isReadyForMoreMediaData { usleep(1000) }
  var pb: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
  let buffer = pb!
  CVPixelBufferLockBaseAddress(buffer, [])
  let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
  let t = Double(i) / Double(frames)
  if i < frames / 2 {
    ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 20 + t * 400, y: 80, width: 60, height: 60))
  } else {
    ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    for k in 0..<4 { ctx.fill(CGRect(x: 30 + k * 70, y: Int(40 + t * 100), width: 40, height: 40)) }
  }
  CVPixelBufferUnlockBaseAddress(buffer, [])
  adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print("status", writer.status.rawValue, writer.error as Any)

import ImageIO
import UniformTypeIdentifiers
let pw = 640, ph = 480
let image = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
image.setFillColor(CGColor(red: 0.55, green: 0.8, blue: 0.95, alpha: 1)); image.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
image.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.25, alpha: 1)); image.fill(CGRect(x: 0, y: 0, width: pw, height: 160))
image.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.1, alpha: 1)); image.fillEllipse(in: CGRect(x: 480, y: 340, width: 90, height: 90))
image.setFillColor(CGColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1)); image.fill(CGRect(x: 120, y: 160, width: 140, height: 120))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/scene.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image.makeImage()!, nil)
print("png", CGImageDestinationFinalize(destination))

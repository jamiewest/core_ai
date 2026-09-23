import AVFoundation
let dir = CommandLine.arguments[1]
let rate = 16000.0
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
for (i, freq) in [220.0, 330, 440, 550, 660, 880, 990, 1200, 1500, 1800, 2200, 2600, 3000, 520, 740].enumerated() {
  let frames = AVAudioFrameCount(rate * 3)
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
  buffer.frameLength = frames
  let data = buffer.floatChannelData![0]
  for n in 0..<Int(frames) { data[n] = Float(0.4 * sin(2 * .pi * freq * Double(n) / rate)) }
  let file = try AVAudioFile(forWriting: URL(fileURLWithPath: "\(dir)/t\(i).wav"), settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
  try file.write(from: buffer)
}

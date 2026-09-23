import SoundAnalysis
import CoreML
final class Obs: NSObject, SNResultsObserving {
  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let r = result as? SNClassificationResult else { return }
    print(String(format: "%.2f+%.2f", r.timeRange.start.seconds, r.timeRange.duration.seconds), r.classifications.map { "\($0.identifier)=\(String(format: "%.2f", $0.confidence))" })
  }
  func request(_ request: SNRequest, didFailWithError error: Error) { print("fail", error) }
}
let compiled = try MLModel.compileModel(at: URL(fileURLWithPath: "SpeechOrTone.mlmodel"))
print("compiled", compiled.path)
let model = try MLModel(contentsOf: compiled)
let req = try SNClassifySoundRequest(mlModel: model)
print("known", req.knownClassifications, "window", req.windowDuration.seconds)
for f in CommandLine.arguments.dropFirst() {
  print(f)
  let a = try SNAudioFileAnalyzer(url: URL(fileURLWithPath: f)); let o = Obs(); try a.add(req, withObserver: o); a.analyze()
}
do { _ = try SNAudioFileAnalyzer(url: URL(fileURLWithPath: "/nonexistent.wav")) } catch { let e = error as NSError; print("missing:", e.domain, e.code, e.localizedDescription) }
do { _ = try SNAudioFileAnalyzer(url: URL(fileURLWithPath: "probe2.swift")) } catch { let e = error as NSError; print("notaudio:", e.domain, e.code, e.localizedDescription) }

import SoundAnalysis
import AVFoundation
final class Obs: NSObject, SNResultsObserving {
  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let r = result as? SNClassificationResult else { return }
    let top = r.classifications.prefix(3).map { "\($0.identifier)=\(String(format: "%.2f", $0.confidence))" }
    print(String(format: "%.2f+%.2f", r.timeRange.start.seconds, r.timeRange.duration.seconds), top)
  }
  func request(_ request: SNRequest, didFailWithError error: Error) { print("fail", error) }
  func requestDidComplete(_ request: SNRequest) { print("complete") }
}
let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
print("labels", req.knownClassifications.count, req.knownClassifications.filter { $0.contains("speech") || $0.contains("sine") || $0.contains("tone") || $0.contains("whistl") || $0.contains("beep") })
print("window", req.windowDuration.seconds, "overlap", req.overlapFactor)
switch req.windowDurationConstraint { case .enumeratedDurations(let d): print("enum", d.map { $0.seconds }); case .durationRange(let r): print("range", r.start.seconds, r.end.seconds) }
let a = try SNAudioFileAnalyzer(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let o = Obs()
try a.add(req, withObserver: o)
a.analyze()

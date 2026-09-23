import CreateML
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let classifier = try MLSoundClassifier(trainingData: .labeledDirectories(at: root))
print("training accuracy", 1 - classifier.trainingMetrics.classificationError)
try classifier.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), metadata: MLModelMetadata(author: "apple_sound_analysis tests", shortDescription: "Speech vs tone", version: "1.0"))

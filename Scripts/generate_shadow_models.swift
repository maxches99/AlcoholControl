import Foundation
import CreateML
import TabularData

let sampleCount = 300

var peakRatio: [Double] = []
var paceRatio: [Double] = []
var hydrationDeficit: [Double] = []
var shortSleep: [Double] = []
var noMeal: [Double] = []
var morningDelta: [Double] = []
var memoryDelta: [Double] = []

for i in 0..<sampleCount {
    let p = Double((i * 37) % 200) / 100.0
    let q = Double((i * 29) % 220) / 100.0
    let h = Double((i * 17) % 101) / 100.0
    let s = ((i * 7) % 10) < 4 ? 1.0 : 0.0
    let m = ((i * 11) % 10) < 5 ? 1.0 : 0.0

    let morningRaw = -1.35 + (0.95 * p) + (0.55 * q) + (0.85 * h) + (0.35 * s) + (0.25 * m)
    let memoryRaw = -1.70 + (1.10 * p) + (0.80 * q) + (0.45 * h) + (0.20 * m)

    peakRatio.append(p)
    paceRatio.append(q)
    hydrationDeficit.append(h)
    shortSleep.append(s)
    noMeal.append(m)
    morningDelta.append(1.0 / (1.0 + exp(-morningRaw)))
    memoryDelta.append(1.0 / (1.0 + exp(-memoryRaw)))
}

let morningData: DataFrame = [
    "peakRatio": peakRatio,
    "paceRatio": paceRatio,
    "hydrationDeficit": hydrationDeficit,
    "shortSleep": shortSleep,
    "noMeal": noMeal,
    "morningDelta": morningDelta
]

let memoryData: DataFrame = [
    "peakRatio": peakRatio,
    "paceRatio": paceRatio,
    "hydrationDeficit": hydrationDeficit,
    "shortSleep": shortSleep,
    "noMeal": noMeal,
    "memoryDelta": memoryDelta
]

let morningRegressor = try MLLinearRegressor(trainingData: morningData, targetColumn: "morningDelta")
let memoryRegressor = try MLLinearRegressor(trainingData: memoryData, targetColumn: "memoryDelta")

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let outputDir = cwd.appendingPathComponent("AlcoholControl/ML", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

try morningRegressor.write(to: outputDir.appendingPathComponent("ShadowMorningRegressor.mlmodel"))
try memoryRegressor.write(to: outputDir.appendingPathComponent("ShadowMemoryRegressor.mlmodel"))

print("Generated CoreML shadow models in \(outputDir.path)")

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
var spiritsFlag: [Double] = []
var lateStart: [Double] = []
var highPeak: [Double] = []
var headacheProbability: [Double] = []
var fatigueProbability: [Double] = []
var heavyMorningProbability: [Double] = []

for i in 0..<sampleCount {
    let p = Double((i * 37) % 200) / 100.0
    let q = Double((i * 29) % 220) / 100.0
    let h = Double((i * 17) % 101) / 100.0
    let s = ((i * 7) % 10) < 4 ? 1.0 : 0.0
    let m = ((i * 11) % 10) < 5 ? 1.0 : 0.0

    let morningRaw = -1.35 + (0.95 * p) + (0.55 * q) + (0.85 * h) + (0.35 * s) + (0.25 * m)
    let memoryRaw = -1.70 + (1.10 * p) + (0.80 * q) + (0.45 * h) + (0.20 * m)
    let spirits = ((i * 13) % 10) < 4 ? 1.0 : 0.0
    let late = Double((i * 23) % 100) / 100.0
    let peak = ((i * 31) % 10) < 5 ? 1.0 : 0.0
    let headacheRaw = -2.15 + (0.95 * spirits) + (0.85 * h) + (0.50 * q) + (0.45 * peak) + (0.20 * m)
    let fatigueRaw = -2.00 + (0.55 * spirits) + (0.75 * late) + (0.70 * q) + (0.40 * h) + (0.35 * m)
    let heavyMorningRaw = -2.10 + (0.80 * spirits) + (0.60 * late) + (0.90 * q) + (0.50 * peak) + (0.20 * m)

    peakRatio.append(p)
    paceRatio.append(q)
    hydrationDeficit.append(h)
    shortSleep.append(s)
    noMeal.append(m)
    morningDelta.append(1.0 / (1.0 + exp(-morningRaw)))
    memoryDelta.append(1.0 / (1.0 + exp(-memoryRaw)))
    spiritsFlag.append(spirits)
    lateStart.append(late)
    highPeak.append(peak)
    headacheProbability.append(1.0 / (1.0 + exp(-headacheRaw)))
    fatigueProbability.append(1.0 / (1.0 + exp(-fatigueRaw)))
    heavyMorningProbability.append(1.0 / (1.0 + exp(-heavyMorningRaw)))
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

let headacheData: DataFrame = [
    "spiritsFlag": spiritsFlag,
    "lateStart": lateStart,
    "paceRatio": paceRatio,
    "hydrationDeficit": hydrationDeficit,
    "highPeak": highPeak,
    "noMeal": noMeal,
    "headacheProbability": headacheProbability
]

let fatigueData: DataFrame = [
    "spiritsFlag": spiritsFlag,
    "lateStart": lateStart,
    "paceRatio": paceRatio,
    "hydrationDeficit": hydrationDeficit,
    "highPeak": highPeak,
    "noMeal": noMeal,
    "fatigueProbability": fatigueProbability
]

let heavyMorningData: DataFrame = [
    "spiritsFlag": spiritsFlag,
    "lateStart": lateStart,
    "paceRatio": paceRatio,
    "hydrationDeficit": hydrationDeficit,
    "highPeak": highPeak,
    "noMeal": noMeal,
    "heavyMorningProbability": heavyMorningProbability
]

let headacheRegressor = try MLLinearRegressor(trainingData: headacheData, targetColumn: "headacheProbability")
let fatigueRegressor = try MLLinearRegressor(trainingData: fatigueData, targetColumn: "fatigueProbability")
let heavyMorningRegressor = try MLLinearRegressor(trainingData: heavyMorningData, targetColumn: "heavyMorningProbability")

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let outputDir = cwd.appendingPathComponent("AlcoholControl/ML", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

try morningRegressor.write(to: outputDir.appendingPathComponent("ShadowMorningRegressor.mlmodel"))
try memoryRegressor.write(to: outputDir.appendingPathComponent("ShadowMemoryRegressor.mlmodel"))
try headacheRegressor.write(to: outputDir.appendingPathComponent("ShadowTrendHeadacheRegressor.mlmodel"))
try fatigueRegressor.write(to: outputDir.appendingPathComponent("ShadowTrendFatigueRegressor.mlmodel"))
try heavyMorningRegressor.write(to: outputDir.appendingPathComponent("ShadowTrendHeavyMorningRegressor.mlmodel"))

print("Generated CoreML shadow models in \(outputDir.path)")

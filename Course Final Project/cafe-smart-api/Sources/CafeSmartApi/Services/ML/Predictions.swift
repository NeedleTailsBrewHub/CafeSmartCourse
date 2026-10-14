//
//  Predictions.swift
//  CafeSmartAPI
//
//  Core ML predictor + registry. CoreML types are gated for Linux builds.
//

import Foundation
import Vapor

#if canImport(CoreML)
import CoreML

final class CoreMLPredictor: PredictorServing, @unchecked Sendable {
    enum Errors: Error {
        case msg(String)
    }

    private let model: MLModel
    private let lock = NSLock()

    init(modelPath: String) async throws {
        let url = URL(fileURLWithPath: modelPath)
        let fm = FileManager.default

        if url.pathExtension == "mlmodel" {
            let compiledURL = try await MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } else if url.pathExtension == "mlmodelc"
            || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            || fm.fileExists(atPath: url.path)
        {
            self.model = try MLModel(contentsOf: url)
        } else {
            throw Errors.msg("Unsupported model file at path: \(modelPath)")
        }
    }

    func ioNames() async throws -> (input: String, output: String) {
        let inName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"
        return (inName, outName)
    }

    func predictMultiple(inputs: [String: PredictorFeature], outputName: String) async throws -> [Float] {
        let provider: MLDictionaryFeatureProvider = try {
            lock.lock()
            defer { lock.unlock() }
            var featureDict: [String: MLFeatureValue] = [:]
            for (inputName, feature) in inputs {
                guard let inputDesc = model.modelDescription.inputDescriptionsByName[inputName] else {
                    throw Errors.msg("Input '\(inputName)' not found in model description")
                }
                let featureValue: MLFeatureValue
                switch (inputDesc.type, feature) {
                case (.double, .double(let v)):
                    featureValue = MLFeatureValue(double: v)
                case (.double, .int(let v)):
                    featureValue = MLFeatureValue(double: Double(v))
                case (.int64, .int(let v)):
                    featureValue = MLFeatureValue(int64: Int64(v))
                case (.int64, .double(let v)):
                    featureValue = MLFeatureValue(int64: Int64(v))
                case (.string, .string(let v)):
                    featureValue = MLFeatureValue(string: v)
                case (.multiArray, .floats(let arrayValue)):
                    let shapeNums = [NSNumber(value: Int64(arrayValue.count))]
                    let array = try MLMultiArray(shape: shapeNums, dataType: .float32)
                    for (index, value) in arrayValue.enumerated() {
                        array[index] = NSNumber(value: value)
                    }
                    featureValue = MLFeatureValue(multiArray: array)
                default:
                    throw Errors.msg("Cannot convert \(feature) to \(inputDesc.type) for '\(inputName)'")
                }
                featureDict[inputName] = featureValue
            }
            return try MLDictionaryFeatureProvider(dictionary: featureDict)
        }()

        let out = try await model.prediction(from: provider as any MLFeatureProvider)

        if let outValue = out.featureValue(for: outputName)?.multiArrayValue {
            let count = outValue.count
            var result = [Float](repeating: 0, count: count)
            let bytes = count * MemoryLayout<Float32>.stride
            memcpy(&result, outValue.dataPointer, bytes)
            return result
        } else if let outValue = out.featureValue(for: outputName)?.doubleValue {
            return [Float(outValue)]
        } else if let targetUsageValue = out.featureValue(for: "target_usage")?.doubleValue {
            return [Float(targetUsageValue)]
        } else if let firstFeature = out.featureNames.first,
                  let firstValue = out.featureValue(for: firstFeature)?.doubleValue
        {
            return [Float(firstValue)]
        } else {
            throw Errors.msg("Output feature not found: \(outputName). Available: \(out.featureNames)")
        }
    }
}
#endif

struct PredictorEntry: Sendable {
    var runtime: PredictRuntime
    var path: String
    var predictor: any PredictorServing
}

actor PredictorRegistry {
    private var predictors: [PredictorKind: PredictorEntry] = [:]

    func set(kind: PredictorKind, runtime: PredictRuntime, path: String, predictor: any PredictorServing) {
        predictors[kind] = PredictorEntry(runtime: runtime, path: path, predictor: predictor)
    }

    func get(_ kind: PredictorKind) -> (any PredictorServing)? {
        predictors[kind]?.predictor
    }

    func entry(_ kind: PredictorKind) -> PredictorEntry? {
        predictors[kind]
    }

    func remove(_ kind: PredictorKind) {
        predictors.removeValue(forKey: kind)
    }

    func clear() {
        predictors.removeAll()
    }
}

extension Application {
    private struct PredictorRegistryKey: StorageKey {
        typealias Value = PredictorRegistry
    }

    var predictors: PredictorRegistry {
        get {
            storage[PredictorRegistryKey.self] ?? {
                let r = PredictorRegistry()
                storage[PredictorRegistryKey.self] = r
                return r
            }()
        }
        set { storage[PredictorRegistryKey.self] = newValue }
    }
}

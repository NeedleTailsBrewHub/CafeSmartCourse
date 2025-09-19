//
//  Predictor.swift
//  CafeSmartApi
//
//  Created by Cole M on 9/5/25.
//
#if canImport(CoreML)
import Foundation
import CoreML

actor Predictor {
    
    let model: MLModel
    
    enum Errors: Error {
        case msg(String)
    }
    
    init(modelPath: String) async throws {
        let url = URL(fileURLWithPath: modelPath)
        
        if url.pathExtension == "mlmodel" {
            let compiledURL = try await MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } else if url.pathExtension == "mlmodelc" {
            self.model = try MLModel(contentsOf: url)
        } else {
            throw Errors.msg("Unsupported model file at path: \(url.path)")
        }
    }
    
    func ioNames() throws -> (String, String) {
        let inName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"
        return (inName, outName)
    }
    
    func predictMultiple(inputs: [String: Any], outputName: String) throws -> [Float] {
        var featureDict: [String: MLFeatureValue] = [:]
        
        // Process each input feature
        for (inputName, inputValue) in inputs {
            // Get model's expected input description
            guard let inputDesc = model.modelDescription.inputDescriptionsByName[inputName] else {
                throw Errors.msg("Input '\(inputName)' not found in model description")
            }
            
            // Create appropriate MLFeatureValue based on expected type
            let featureValue: MLFeatureValue
            switch inputDesc.type {
            case .double:
                // Handle Double inputs with type conversion
                if let doubleValue = inputValue as? Double {
                    featureValue = MLFeatureValue(double: doubleValue)
                } else if let floatValue = inputValue as? Float {
                    featureValue = MLFeatureValue(double: Double(floatValue))
                } else if let intValue = inputValue as? Int {
                    featureValue = MLFeatureValue(double: Double(intValue))
                } else {
                    throw Errors.msg("Cannot convert \(type(of: inputValue)) to double for '\(inputName)'")
                }
                
            case .int64:
                // Handle Int64 inputs with type conversion
                if let intValue = inputValue as? Int {
                    featureValue = MLFeatureValue(int64: Int64(intValue))
                } else if let doubleValue = inputValue as? Double {
                    featureValue = MLFeatureValue(int64: Int64(doubleValue))
                } else {
                    throw Errors.msg("Cannot convert \(type(of: inputValue)) to int64 for '\(inputName)'")
                }
                
            case .string:
                // Handle String inputs
                if let stringValue = inputValue as? String {
                    featureValue = MLFeatureValue(string: stringValue)
                } else {
                    throw Errors.msg("Cannot convert \(type(of: inputValue)) to string for '\(inputName)'")
                }
                
            case .multiArray:
                // Handle MultiArray inputs (typically arrays of floats)
                if let arrayValue = inputValue as? [Float] {
                    let shapeNums = [NSNumber(value: Int64(arrayValue.count))]
                    let array = try MLMultiArray(shape: shapeNums, dataType: .float32)
                    for (index, value) in arrayValue.enumerated() {
                        array[index] = NSNumber(value: value)
                    }
                    featureValue = MLFeatureValue(multiArray: array)
                } else {
                    throw Errors.msg("Cannot convert \(type(of: inputValue)) to multiArray for '\(inputName)'")
                }
                
            default:
                throw Errors.msg("Unsupported input type: \(inputDesc.type) for '\(inputName)'")
            }
            
            featureDict[inputName] = featureValue
        }
        
        // Create feature provider and make prediction
        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let out = try model.prediction(from: provider)
        
        // Extract output with robust fallback logic
        if let outValue = out.featureValue(for: outputName)?.multiArrayValue {
            // Output is a multi-array
            let count = outValue.count
            var result = [Float](repeating: 0, count: count)
            let bytes = count * MemoryLayout<Float32>.stride
            memcpy(&result, outValue.dataPointer, bytes)
            return result
        } else if let outValue = out.featureValue(for: outputName)?.doubleValue {
            // Output is a single double
            return [Float(outValue)]
        } else if let targetUsageValue = out.featureValue(for: "target_usage")?.doubleValue {
            // Fallback to common output name "target_usage"
            return [Float(targetUsageValue)]
        } else if let firstFeature = out.featureNames.first,
                  let firstValue = out.featureValue(for: firstFeature)?.doubleValue {
            // Fallback to first available output feature
            return [Float(firstValue)]
        } else {
            throw Errors.msg("Output feature not found: \(outputName). Available: \(out.featureNames)")
        }
    }
}
#endif

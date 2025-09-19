//
//  Predictions.swift
//  CafeSmartAPI
//
//  Core ML Prediction Service
//  =========================
//  
//  This file demonstrates how to integrate Core ML models into a Vapor API.
//  It shows the complete workflow from model loading to making predictions.
//
//  Key Concepts Covered:
//  - MLModel: Core ML's model representation
//  - MLFeatureValue: Wrapper for different data types (Double, Int64, String, MultiArray)
//  - MLDictionaryFeatureProvider: Provides input features to models
//  - MLMultiArray: Multi-dimensional arrays for numerical data
//  - Model compilation and loading
//  - Type-safe prediction methods
//
//  Teaching Focus:
//  - Core ML fundamentals
//  - Type safety in ML predictions
//  - Error handling for ML operations
//  - Async/await patterns with ML models
//

import Foundation
import Vapor
import CoreML

// MARK: - Core ML Predictor Actor
// ==============================

/// Core ML Predictor for making machine learning predictions
/// 
/// This actor encapsulates a Core ML model and provides type-safe methods
/// for making predictions. It handles model loading, compilation, and
/// provides a clean interface for different input types.
///
/// Key Features:
/// - Automatic model compilation from .mlmodel to .mlmodelc
/// - Type-safe prediction methods for different input types
/// - Comprehensive error handling
/// - Thread-safe operations (actor-based)
actor Predictor {
    
    // MARK: - Error Types
    
    /// Custom errors for prediction operations
    enum Errors: Error {
        case msg(String)
    }
    
    // MARK: - Properties
    
    /// The loaded Core ML model
    private let model: MLModel
    
    // MARK: - Initialization
    
    /// Initialize the predictor with a model file path
    /// 
    /// This method handles:
    /// 1. Loading .mlmodel files and compiling them to .mlmodelc
    /// 2. Loading already compiled .mlmodelc files
    /// 3. Validating file existence and format
    ///
    /// - Parameter modelPath: Path to the Core ML model file
    /// - Throws: Errors if model cannot be loaded or compiled
    init(modelPath: String) async throws {
        let url = URL(fileURLWithPath: modelPath)
        let fm = FileManager.default
        
        // Handle different model file types
        if url.pathExtension == "mlmodel" {
            // Compile .mlmodel to .mlmodelc format
            let compiledURL = try await MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } else if url.pathExtension == "mlmodelc" || 
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || 
                  (fm.fileExists(atPath: url.path, isDirectory: nil)) {
            // Load already compiled model
            self.model = try MLModel(contentsOf: url)
        } else {
            throw Errors.msg("Unsupported model file at path: \(modelPath)")
        }
    }
    
    // MARK: - Model Information
    
    /// Get the input and output feature names from the model
    /// 
    /// This method extracts the first input and output feature names
    /// from the model description. It's useful for understanding
    /// what the model expects as input and produces as output.
    ///
    /// - Returns: Tuple of (inputName, outputName)
    /// - Throws: Errors if model description is invalid
    func ioNames() throws -> (String, String) {
        let inName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"
        return (inName, outName)
    }

    // MARK: - Multiple Input Prediction
    // ================================
    
    /// Make a prediction with multiple input features
    /// 
    /// This is the most flexible prediction method, allowing you to provide
    /// multiple features of different types (Double, Int64, String, MultiArray)
    /// in a single prediction call. It automatically handles type conversion
    /// based on the model's expected input types.
    ///
    /// This method is particularly useful for tabular data models that expect
    /// multiple features like: usage_lag_1d (Double), sku (String), day (Int), etc.
    ///
    /// - Parameters:
    ///   - inputs: Dictionary of feature names to values
    ///   - outputName: Name of the output feature to extract
    /// - Returns: Array of predicted float values
    /// - Throws: Errors for invalid inputs, type mismatches, or model failures
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

// MARK: - Predictor Registry
// =========================

/// Registry for managing multiple predictor instances
/// 
/// This actor provides a thread-safe way to store and retrieve
/// predictor instances by their kind (e.g., restockDaily, demandForecast).
/// It's used by the application to manage different ML models.
actor PredictorRegistry {
    
    /// Storage for predictor instances
    private var predictors: [PredictorKind: Predictor] = [:]
    
    /// Set a predictor for a specific kind
    func set(kind: PredictorKind, runtime: PredictRuntime, path: String, predictor: Predictor) {
        predictors[kind] = predictor
    }
    
    /// Get a predictor for a specific kind
    func get(_ kind: PredictorKind) -> Predictor? {
        return predictors[kind]
    }
    
    /// Remove a predictor for a specific kind
    func remove(_ kind: PredictorKind) {
        predictors.removeValue(forKey: kind)
    }
    
    /// Clear all predictors
    func clear() {
        predictors.removeAll()
    }
}

// MARK: - Application Extension
// ============================

/// Extension to provide predictor registry access on Application
extension Application {
    private struct PredictorRegistryKey: StorageKey { 
        typealias Value = PredictorRegistry 
    }
    
    /// Access to the predictor registry
    var predictors: PredictorRegistry {
        get { 
            storage[PredictorRegistryKey.self] ?? { 
                let r = PredictorRegistry(); 
                storage[PredictorRegistryKey.self] = r; 
                return r 
            }() 
        }
        set { storage[PredictorRegistryKey.self] = newValue }
    }
}

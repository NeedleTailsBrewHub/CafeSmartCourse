//
//  AIModels.swift
//  CafeSmartDev
//

import Foundation

public struct PredictorCapabilities: Codable, Sendable, Equatable {
    public var coremlInference: Bool
    public var onnxInference: Bool
    public var serverTraining: Bool
}

/// Where restock training runs. Local Create ML is macOS-only; server works on all clients.
public enum TrainingLocation: String, Sendable {
    case local
    case server
}

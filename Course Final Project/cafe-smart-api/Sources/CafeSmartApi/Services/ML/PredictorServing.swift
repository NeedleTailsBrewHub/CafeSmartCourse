import Foundation

/// Typed feature values passed into predictors (Swift 6–friendly).
public enum PredictorFeature: Sendable, Equatable {
    case double(Double)
    case int(Int)
    case string(String)
    case floats([Float])
}

/// Shared restock feature names used by export CSV, forecastSeries, trainer, and ONNX contract checks.
public enum RestockFeatureContract {
    public static let requiredInputNames: [String] = [
        "usage_lag_1d",
        "sku",
        "day",
        "weekday",
        "month",
        "orders_total_lag_1d",
        "year",
        "usage_lag_7d",
        "items_total_lag_1d",
        "rolling_usage_last_7d",
        "usage_same_weekday_lag_28d",
    ]

    public static let targetName = "target_usage"
}

public protocol PredictorServing: Sendable {
    func ioNames() async throws -> (input: String, output: String)
    func predictMultiple(inputs: [String: PredictorFeature], outputName: String) async throws -> [Float]
}

public enum PredictorError: Error, CustomStringConvertible, Sendable {
    case unavailable(PredictRuntime)
    case unsupportedModel(String)
    case msg(String)

    public var description: String {
        switch self {
        case .unavailable(let runtime):
            return "Predictor runtime unavailable on this host: \(runtime.rawValue)"
        case .unsupportedModel(let detail):
            return detail
        case .msg(let detail):
            return detail
        }
    }
}

actor MockPredictor: PredictorServing {
    private let output: [Float]
    private let inputName: String
    private let outputName: String

    init(output: [Float] = [1.0], inputName: String = "input", outputName: String = "output") {
        self.output = output
        self.inputName = inputName
        self.outputName = outputName
    }

    func ioNames() async throws -> (input: String, output: String) {
        (inputName, outputName)
    }

    func predictMultiple(inputs: [String: PredictorFeature], outputName: String) async throws -> [Float] {
        _ = inputs
        _ = outputName
        return output
    }
}

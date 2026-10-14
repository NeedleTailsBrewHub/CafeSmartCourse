import Foundation

/// Typed feature values passed into predictors (Swift 6–friendly).
public enum PredictorFeature: Sendable, Equatable {
    case double(Double)
    case int(Int)
    case string(String)
    case floats([Float])
}

/// Shared feature-name contract used by CSV export, trainers, and ONNX checks.
public struct FeatureContractSpec: Sendable, Equatable {
    public let requiredInputNames: [String]
    public let targetName: String

    public init(requiredInputNames: [String], targetName: String) {
        self.requiredInputNames = requiredInputNames
        self.targetName = targetName
    }

    public static func forKind(_ kind: PredictorKind) -> FeatureContractSpec {
        switch kind {
        case .restockDaily:
            return RestockFeatureContract.spec
        case .workloadHourly:
            return WorkloadFeatureContract.spec
        case .reservationsHourly:
            return ReservationsFeatureContract.spec
        case .reservationDuration:
            // Not wired for training/inference yet; keep a restock-shaped fallback for load checks.
            return RestockFeatureContract.spec
        }
    }
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

    public static var spec: FeatureContractSpec {
        FeatureContractSpec(requiredInputNames: requiredInputNames, targetName: targetName)
    }
}

/// Workload (orders hourly) feature contract.
public enum WorkloadFeatureContract {
    public static let requiredInputNames: [String] = [
        "orders_lag_1h",
        "orders_lag_24h",
        "orders_lag_168h",
        "rolling_orders_24h",
        "covers_lag_1h",
        "covers_lag_24h",
        "year",
        "month",
        "day",
        "hour",
        "weekday",
    ]

    public static let targetName = "target_orders"

    public static var spec: FeatureContractSpec {
        FeatureContractSpec(requiredInputNames: requiredInputNames, targetName: targetName)
    }
}

/// Reservations hourly feature contract.
public enum ReservationsFeatureContract {
    public static let requiredInputNames: [String] = [
        "covers_lag_1h",
        "covers_lag_24h",
        "covers_lag_168h",
        "rolling_covers_24h",
        "reservations_lag_1h",
        "reservations_lag_24h",
        "year",
        "month",
        "day",
        "hour",
        "weekday",
    ]

    public static let targetName = "target_covers"

    public static var spec: FeatureContractSpec {
        FeatureContractSpec(requiredInputNames: requiredInputNames, targetName: targetName)
    }
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

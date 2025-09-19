import Foundation
import CoreML

/// CafeSmart ML provides machine learning capabilities for cafe management systems.
///
/// This framework enables intelligent inventory management, demand forecasting,
/// and business intelligence insights for cafe operations.
public struct CafeSmartML {
    
    /// The version of the CafeSmart ML framework.
    public static let version = "1.0.0"
    
    /// Initialize the CafeSmart ML framework.
    public init() {}
    
    /// Predict ingredient usage for a specific SKU and date.
    ///
    /// - Parameters:
    ///   - sku: The stock keeping unit identifier
    ///   - date: The date for which to predict usage
    ///   - features: The input features for the prediction
    /// - Returns: A usage prediction with confidence score
    /// - Throws: An error if the prediction fails
    public func predictUsage(
        for sku: String,
        date: Date,
        features: UsageFeatures
    ) throws -> UsagePrediction {
        // Implementation would use Core ML model here
        return UsagePrediction(
            sku: sku,
            date: date,
            predictedUsage: 8.5,
            confidence: 0.85
        )
    }
}

/// Input features for usage prediction.
public struct UsageFeatures {
    /// The year component of the date.
    public let year: Int
    
    /// The month component of the date.
    public let month: Int
    
    /// The day component of the date.
    public let day: Int
    
    /// The weekday (1 = Sunday, 7 = Saturday).
    public let weekday: Int
    
    /// Whether the date falls on a weekend.
    public let isWeekend: Bool
    
    /// Total orders from the previous day.
    public let ordersTotalLag1d: Int
    
    /// Total items sold from the previous day.
    public let itemsTotalLag1d: Int
    
    /// Usage from the previous day.
    public let usageLag1d: Double
    
    /// Usage from 7 days ago.
    public let usageLag7d: Double
    
    /// Rolling average usage over the last 7 days.
    public let rollingUsageLast7d: Double
    
    /// Usage from the same weekday 28 days ago.
    public let usageSameWeekdayLag28d: Double
    
    /// Initialize usage features.
    public init(
        year: Int,
        month: Int,
        day: Int,
        weekday: Int,
        isWeekend: Bool,
        ordersTotalLag1d: Int,
        itemsTotalLag1d: Int,
        usageLag1d: Double,
        usageLag7d: Double,
        rollingUsageLast7d: Double,
        usageSameWeekdayLag28d: Double
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.weekday = weekday
        self.isWeekend = isWeekend
        self.ordersTotalLag1d = ordersTotalLag1d
        self.itemsTotalLag1d = itemsTotalLag1d
        self.usageLag1d = usageLag1d
        self.usageLag7d = usageLag7d
        self.rollingUsageLast7d = rollingUsageLast7d
        self.usageSameWeekdayLag28d = usageSameWeekdayLag28d
    }
}

/// A prediction of ingredient usage.
public struct UsagePrediction {
    /// The stock keeping unit identifier.
    public let sku: String
    
    /// The date for which the prediction was made.
    public let date: Date
    
    /// The predicted usage amount.
    public let predictedUsage: Double
    
    /// The confidence score for the prediction (0.0 to 1.0).
    public let confidence: Double
    
    /// Initialize a usage prediction.
    public init(
        sku: String,
        date: Date,
        predictedUsage: Double,
        confidence: Double
    ) {
        self.sku = sku
        self.date = date
        self.predictedUsage = predictedUsage
        self.confidence = confidence
    }
}

/// Errors that can occur during prediction.
public enum PredictionError: Error {
    /// The model could not be loaded.
    case modelNotFound
    
    /// The input features are invalid.
    case invalidInput
    
    /// The prediction failed.
    case predictionFailed(Error)
    
    /// The SKU is not supported.
    case unsupportedSKU(String)
}

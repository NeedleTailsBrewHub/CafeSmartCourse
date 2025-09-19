# Core ML Integration Guide

Learn how to integrate CafeSmart ML models into your iOS applications using Core ML.

## Overview

CafeSmart ML provides Core ML models that can be integrated directly into iOS applications for on-device predictions. This guide covers the technical implementation details for using these models.

## Model Architecture

### Model Structure

The CafeSmart ML models are trained using scikit-learn and converted to Core ML format:

```swift
import CoreML

// Load the model
guard let model = try? RestockDaily() else {
    fatalError("Failed to load model")
}
```

### Input Features

The model expects the following input features:

```swift
struct ModelInput {
    let year: Int
    let month: Int
    let day: Int
    let weekday: Int
    let isWeekend: Bool
    let ordersTotalLag1d: Int
    let itemsTotalLag1d: Int
    let usageLag1d: Double
    let usageLag7d: Double
    let rollingUsageLast7d: Double
    let usageSameWeekdayLag28d: Double
}
```

### Output Prediction

The model outputs usage predictions:

```swift
struct ModelOutput {
    let predictedUsage: Double
    let confidence: Double
}
```

## Integration Steps

### 1. Add Model to Project

1. Drag the `.mlmodel` file into your Xcode project
2. Ensure "Add to target" is checked for your app target
3. Xcode will automatically generate Swift wrapper classes

### 2. Import Core ML

```swift
import CoreML
import Foundation
```

### 3. Load Model

```swift
class CafeSmartPredictor {
    private let model: RestockDaily
    
    init() throws {
        self.model = try RestockDaily()
    }
}
```

### 4. Prepare Input Data

```swift
func prepareInput(for sku: String, date: Date) -> ModelInput {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
    
    return ModelInput(
        year: components.year ?? 2025,
        month: components.month ?? 1,
        day: components.day ?? 1,
        weekday: components.weekday ?? 1,
        isWeekend: calendar.isDateInWeekend(date),
        ordersTotalLag1d: getOrdersTotalLag1d(),
        itemsTotalLag1d: getItemsTotalLag1d(),
        usageLag1d: getUsageLag1d(for: sku),
        usageLag7d: getUsageLag7d(for: sku),
        rollingUsageLast7d: getRollingUsageLast7d(for: sku),
        usageSameWeekdayLag28d: getUsageSameWeekdayLag28d(for: sku)
    )
}
```

### 5. Make Predictions

```swift
func predictUsage(for sku: String, date: Date) throws -> UsagePrediction {
    let input = prepareInput(for: sku, date: date)
    
    let prediction = try model.prediction(
        year: input.year,
        month: input.month,
        day: input.day,
        weekday: input.weekday,
        isWeekend: input.isWeekend,
        ordersTotalLag1d: input.ordersTotalLag1d,
        itemsTotalLag1d: input.itemsTotalLag1d,
        usageLag1d: input.usageLag1d,
        usageLag7d: input.usageLag7d,
        rollingUsageLast7d: input.rollingUsageLast7d,
        usageSameWeekdayLag28d: input.usageSameWeekdayLag28d
    )
    
    return UsagePrediction(
        sku: sku,
        date: date,
        predictedUsage: prediction.predictedUsage,
        confidence: prediction.confidence
    )
}
```

## Data Management

### Historical Data Storage

Store historical data for feature calculation:

```swift
struct UsageRecord {
    let sku: String
    let date: Date
    let usage: Double
    let ordersTotal: Int
    let itemsTotal: Int
}

class DataManager {
    private var usageRecords: [UsageRecord] = []
    
    func addUsageRecord(_ record: UsageRecord) {
        usageRecords.append(record)
    }
    
    func getUsageLag1d(for sku: String) -> Double {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return usageRecords
            .first { $0.sku == sku && Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
            ?.usage ?? 0.0
    }
}
```

### Feature Calculation

Implement feature calculation methods:

```swift
extension DataManager {
    func getUsageLag7d(for sku: String) -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return usageRecords
            .first { $0.sku == sku && Calendar.current.isDate($0.date, inSameDayAs: weekAgo) }
            ?.usage ?? 0.0
    }
    
    func getRollingUsageLast7d(for sku: String) -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentRecords = usageRecords.filter { 
            $0.sku == sku && $0.date >= weekAgo 
        }
        return recentRecords.map { $0.usage }.reduce(0, +) / 7.0
    }
}
```

## Error Handling

### Model Errors

Handle potential model errors:

```swift
enum PredictionError: Error {
    case modelNotFound
    case invalidInput
    case predictionFailed(Error)
}

func safePredict(for sku: String, date: Date) -> Result<UsagePrediction, PredictionError> {
    do {
        let prediction = try predictUsage(for: sku, date: date)
        return .success(prediction)
    } catch {
        return .failure(.predictionFailed(error))
    }
}
```

### Input Validation

Validate input data before prediction:

```swift
func validateInput(_ input: ModelInput) -> Bool {
    return input.year >= 2020 && input.year <= 2030 &&
           input.month >= 1 && input.month <= 12 &&
           input.day >= 1 && input.day <= 31 &&
           input.weekday >= 1 && input.weekday <= 7
}
```

## Performance Optimization

### Batch Predictions

Make multiple predictions efficiently:

```swift
func predictBatch(for skus: [String], date: Date) -> [UsagePrediction] {
    return skus.compactMap { sku in
        try? predictUsage(for: sku, date: date)
    }
}
```

### Caching

Cache frequently used data:

```swift
class PredictionCache {
    private var cache: [String: UsagePrediction] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    
    func getCachedPrediction(for sku: String) -> UsagePrediction? {
        guard let prediction = cache[sku],
              Date().timeIntervalSince(prediction.date) < cacheExpiration else {
            return nil
        }
        return prediction
    }
    
    func cachePrediction(_ prediction: UsagePrediction) {
        cache[prediction.sku] = prediction
    }
}
```

## Testing

### Unit Tests

Test model integration:

```swift
class CafeSmartPredictorTests: XCTestCase {
    var predictor: CafeSmartPredictor!
    
    override func setUp() {
        super.setUp()
        predictor = try! CafeSmartPredictor()
    }
    
    func testPrediction() throws {
        let prediction = try predictor.predictUsage(
            for: "BEANS-ESP-1KG",
            date: Date()
        )
        
        XCTAssertGreaterThan(prediction.predictedUsage, 0)
        XCTAssertGreaterThanOrEqual(prediction.confidence, 0)
        XCTAssertLessThanOrEqual(prediction.confidence, 1)
    }
}
```

### Integration Tests

Test with real data:

```swift
func testWithHistoricalData() throws {
    // Load historical data
    let historicalData = loadHistoricalData()
    
    for record in historicalData {
        let prediction = try predictor.predictUsage(
            for: record.sku,
            date: record.date
        )
        
        // Validate prediction is reasonable
        XCTAssertGreaterThan(prediction.predictedUsage, 0)
    }
}
```

## Best Practices

### Model Updates

- Monitor model performance in production
- Retrain models with new data periodically
- Version control model files
- Test new models before deployment

### Performance

- Use background queues for predictions
- Cache frequently accessed data
- Implement proper error handling
- Monitor memory usage

### Security

- Validate all input data
- Sanitize user inputs
- Use secure storage for sensitive data
- Implement proper access controls

---

*Core ML integration enables on-device predictions for real-time cafe management decisions.*

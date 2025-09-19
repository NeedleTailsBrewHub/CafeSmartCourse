# Understanding ML Predictions

Learn how CafeSmart ML generates predictions and how to interpret the results.

## Overview

CafeSmart ML uses machine learning models to predict ingredient usage based on historical data, business patterns, and temporal features. Understanding how these predictions work is crucial for making informed business decisions.

## Prediction Process

### Data Flow

```
Raw Data → Feature Engineering → Model Input → Prediction → Business Decision
```

### Model Architecture

The prediction system uses a multi-stage approach:

1. **Feature Engineering**: Transform raw data into meaningful features
2. **Model Training**: Train models on historical data
3. **Prediction Generation**: Generate daily usage predictions
4. **Business Logic**: Apply business rules to predictions

## Feature Categories

### Temporal Features

Temporal features capture time-based patterns:

```swift
struct TemporalFeatures {
    let year: Int
    let month: Int
    let day: Int
    let weekday: Int
    let isWeekend: Bool
}
```

### Lag Features

Lag features capture historical patterns:

```swift
struct LagFeatures {
    let usageLag1d: Double
    let usageLag7d: Double
    let usageLag28d: Double
    let rollingUsageLast7d: Double
}
```

### Volume Features

Volume features capture customer behavior:

```swift
struct VolumeFeatures {
    let ordersTotalLag1d: Int
    let itemsTotalLag1d: Int
}
```

## Prediction Output

### Usage Prediction

The model predicts daily ingredient usage:

```swift
struct UsagePrediction {
    let sku: String
    let date: Date
    let predictedUsage: Double
    let confidence: Double
    let factors: [String: Double]
}
```

### Business Interpretation

Predictions are used for:

- **Inventory Planning**: Determine reorder quantities
- **Staff Scheduling**: Anticipate busy periods
- **Cost Optimization**: Minimize waste and over-ordering
- **Customer Experience**: Ensure product availability

## Model Performance

### Accuracy Metrics

- **Mean Absolute Error (MAE)**: Average prediction error
- **Root Mean Square Error (RMSE)**: Penalizes larger errors
- **R-squared**: Proportion of variance explained

### Business Impact

- **Reduced Waste**: 15-20% reduction in ingredient waste
- **Improved Availability**: 95%+ product availability
- **Cost Savings**: 10-15% reduction in inventory costs

## API Integration

### Prediction Endpoint

```swift
POST /api/predictions/usage
{
    "sku": "BEANS-ESP-1KG",
    "date": "2025-09-01",
    "features": {
        "year": 2025,
        "month": 9,
        "day": 1,
        "weekday": 2,
        "isWeekend": false,
        "ordersTotalLag1d": 45,
        "itemsTotalLag1d": 127,
        "usageLag1d": 8.5,
        "usageLag7d": 7.2,
        "rollingUsageLast7d": 7.8,
        "usageSameWeekdayLag28d": 6.9
    }
}
```

### Response Format

```swift
{
    "prediction": {
        "sku": "BEANS-ESP-1KG",
        "date": "2025-09-01",
        "predictedUsage": 8.2,
        "confidence": 0.85,
        "factors": {
            "temporal": 0.3,
            "historical": 0.4,
            "volume": 0.2,
            "trend": 0.1
        }
    }
}
```

## Best Practices

### Model Monitoring

- Track prediction accuracy over time
- Monitor for data drift
- Validate business assumptions
- Update models with new data

### Business Integration

- Align predictions with business goals
- Communicate uncertainty to stakeholders
- Use predictions as guidance, not absolute truth
- Continuously improve based on feedback

---

*Understanding ML predictions helps you make better business decisions and optimize cafe operations.*

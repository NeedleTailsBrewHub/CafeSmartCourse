# Using the CafeSmart ML Predictions API

Learn how to integrate machine learning predictions into your cafe management system using the CafeSmart ML API.

## Overview

This tutorial teaches you how to use the CafeSmart ML Predictions API to get intelligent recommendations for inventory management, demand forecasting, and business optimization.

## Learning Objectives

By the end of this tutorial, you will be able to:

- Understand the API endpoints and their purposes
- Make predictions for ingredient usage
- Handle API responses and errors
- Integrate predictions into your application
- Monitor prediction accuracy and performance

## Prerequisites

- Basic understanding of REST APIs
- Familiarity with JSON data format
- Knowledge of HTTP methods (GET, POST)
- Understanding of authentication concepts

---

## Understanding the Predictions API

### What the API Does

The CafeSmart ML Predictions API provides intelligent forecasts for:

- **Ingredient Usage**: Predict daily consumption of ingredients
- **Demand Forecasting**: Anticipate customer demand patterns
- **Inventory Optimization**: Recommend reorder quantities
- **Business Intelligence**: Provide insights for decision making

### API Base URL

```
http://localhost:8080/api
```

### Authentication

All API requests require authentication using API keys:

```http
Authorization: Bearer YOUR_API_KEY
```

---

## Tutorial: Getting Started with Predictions

### Step 1: Setting Up Your Environment

First, let's set up the tools you'll need to work with the API.

#### Option A: Using cURL (Command Line)

```bash
# Test your API connection
curl -H "Authorization: Bearer YOUR_API_KEY" \
     http://localhost:8080/api/health
```

#### Option B: Using Swift (iOS/macOS)

```swift
import Foundation

class CafeSmartAPI {
    private let baseURL = "http://localhost:8080/api"
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    private func makeRequest<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int)
}
```

#### Option C: Using Python

```python
import requests
import json

class CafeSmartAPI:
    def __init__(self, api_key, base_url="http://localhost:8080/api"):
        self.api_key = api_key
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
    
    def make_request(self, endpoint, method="GET", data=None):
        url = f"{self.base_url}{endpoint}"
        
        if method == "GET":
            response = requests.get(url, headers=self.headers)
        elif method == "POST":
            response = requests.post(url, headers=self.headers, json=data)
        
        response.raise_for_status()
        return response.json()
```

### Step 2: Checking API Health

Before making predictions, let's verify the API is working correctly.

#### Health Check Endpoint

```http
GET /api/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-09-01T12:00:00Z",
  "version": "1.0.0",
  "services": {
    "predictions": "operational",
    "models": "operational",
    "database": "operational"
  }
}
```

#### Testing the Health Check

**cURL:**
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     http://localhost:8080/api/health
```

**Swift:**
```swift
struct HealthResponse: Codable {
    let status: String
    let timestamp: String
    let version: String
    let services: [String: String]
}

let health: HealthResponse = try await api.makeRequest(endpoint: "/health")
print("API Status: \(health.status)")
```

**Python:**
```python
health = api.make_request("/health")
print(f"API Status: {health['status']}")
```

---

## Tutorial: Making Your First Prediction

### Step 3: Understanding Prediction Inputs

Before making predictions, you need to understand what data the API expects.

#### Required Input Features

```json
{
  "sku": "BEANS-ESP-1KG",
  "date": "2025-09-01",
  "features": {
    "year": 2025,
    "month": 9,
    "day": 1,
    "weekday": 2,
    "is_weekend": false,
    "orders_total_lag_1d": 45,
    "items_total_lag_1d": 127,
    "usage_lag_1d": 8.5,
    "usage_lag_7d": 7.2,
    "rolling_usage_last_7d": 7.8,
    "usage_same_weekday_lag_28d": 6.9
  }
}
```

#### Feature Descriptions

| Feature | Description | Example |
|---------|-------------|---------|
| `sku` | Stock keeping unit identifier | "BEANS-ESP-1KG" |
| `date` | Prediction date (YYYY-MM-DD) | "2025-09-01" |
| `year` | Year component | 2025 |
| `month` | Month (1-12) | 9 |
| `day` | Day of month (1-31) | 1 |
| `weekday` | Day of week (1=Sunday, 7=Saturday) | 2 |
| `is_weekend` | Boolean for weekend days | false |
| `orders_total_lag_1d` | Total orders from yesterday | 45 |
| `items_total_lag_1d` | Total items sold yesterday | 127 |
| `usage_lag_1d` | Ingredient usage from yesterday | 8.5 |
| `usage_lag_7d` | Ingredient usage from 7 days ago | 7.2 |
| `rolling_usage_last_7d` | Average usage over last 7 days | 7.8 |
| `usage_same_weekday_lag_28d` | Usage from same weekday 28 days ago | 6.9 |

### Step 4: Making a Single Prediction

#### Prediction Endpoint

```http
POST /api/predictions/usage
```

#### Request Example

```json
{
  "sku": "BEANS-ESP-1KG",
  "date": "2025-09-01",
  "features": {
    "year": 2025,
    "month": 9,
    "day": 1,
    "weekday": 2,
    "is_weekend": false,
    "orders_total_lag_1d": 45,
    "items_total_lag_1d": 127,
    "usage_lag_1d": 8.5,
    "usage_lag_7d": 7.2,
    "rolling_usage_last_7d": 7.8,
    "usage_same_weekday_lag_28d": 6.9
  }
}
```

#### Response Example

```json
{
  "prediction": {
    "sku": "BEANS-ESP-1KG",
    "date": "2025-09-01",
    "predicted_usage": 8.2,
    "confidence": 0.85,
    "factors": {
      "temporal": 0.3,
      "historical": 0.4,
      "volume": 0.2,
      "trend": 0.1
    },
    "recommendations": {
      "reorder_quantity": 15.0,
      "safety_stock": 2.0,
      "reorder_point": 5.0
    }
  },
  "metadata": {
    "model_version": "1.0.0",
    "prediction_timestamp": "2025-09-01T12:00:00Z",
    "processing_time_ms": 45
  }
}
```

#### Implementation Examples

**cURL:**
```bash
curl -X POST \
     -H "Authorization: Bearer YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "sku": "BEANS-ESP-1KG",
       "date": "2025-09-01",
       "features": {
         "year": 2025,
         "month": 9,
         "day": 1,
         "weekday": 2,
         "is_weekend": false,
         "orders_total_lag_1d": 45,
         "items_total_lag_1d": 127,
         "usage_lag_1d": 8.5,
         "usage_lag_7d": 7.2,
         "rolling_usage_last_7d": 7.8,
         "usage_same_weekday_lag_28d": 6.9
       }
     }' \
     http://localhost:8080/api/predictions/usage
```

**Swift:**
```swift
struct PredictionRequest: Codable {
    let sku: String
    let date: String
    let features: UsageFeatures
}

struct PredictionResponse: Codable {
    let prediction: UsagePrediction
    let metadata: PredictionMetadata
}

struct UsagePrediction: Codable {
    let sku: String
    let date: String
    let predictedUsage: Double
    let confidence: Double
    let factors: [String: Double]
    let recommendations: Recommendations
}

struct Recommendations: Codable {
    let reorderQuantity: Double
    let safetyStock: Double
    let reorderPoint: Double
}

struct PredictionMetadata: Codable {
    let modelVersion: String
    let predictionTimestamp: String
    let processingTimeMs: Int
}

// Make prediction
let request = PredictionRequest(
    sku: "BEANS-ESP-1KG",
    date: "2025-09-01",
    features: usageFeatures
)

let requestData = try JSONEncoder().encode(request)
let response: PredictionResponse = try await api.makeRequest(
    endpoint: "/predictions/usage",
    method: "POST",
    body: requestData
)

print("Predicted Usage: \(response.prediction.predictedUsage)")
print("Confidence: \(response.prediction.confidence)")
```

**Python:**
```python
prediction_data = {
    "sku": "BEANS-ESP-1KG",
    "date": "2025-09-01",
    "features": {
        "year": 2025,
        "month": 9,
        "day": 1,
        "weekday": 2,
        "is_weekend": False,
        "orders_total_lag_1d": 45,
        "items_total_lag_1d": 127,
        "usage_lag_1d": 8.5,
        "usage_lag_7d": 7.2,
        "rolling_usage_last_7d": 7.8,
        "usage_same_weekday_lag_28d": 6.9
    }
}

response = api.make_request("/predictions/usage", method="POST", data=prediction_data)
print(f"Predicted Usage: {response['prediction']['predicted_usage']}")
print(f"Confidence: {response['prediction']['confidence']}")
```

---

## Tutorial: Batch Predictions

### Step 5: Making Multiple Predictions

For efficiency, you can make predictions for multiple SKUs or dates at once.

#### Batch Prediction Endpoint

```http
POST /api/predictions/usage/batch
```

#### Request Example

```json
{
  "predictions": [
    {
      "sku": "BEANS-ESP-1KG",
      "date": "2025-09-01",
      "features": {
        "year": 2025,
        "month": 9,
        "day": 1,
        "weekday": 2,
        "is_weekend": false,
        "orders_total_lag_1d": 45,
        "items_total_lag_1d": 127,
        "usage_lag_1d": 8.5,
        "usage_lag_7d": 7.2,
        "rolling_usage_last_7d": 7.8,
        "usage_same_weekday_lag_28d": 6.9
      }
    },
    {
      "sku": "DAIRY-MILK-1L",
      "date": "2025-09-01",
      "features": {
        "year": 2025,
        "month": 9,
        "day": 1,
        "weekday": 2,
        "is_weekend": false,
        "orders_total_lag_1d": 45,
        "items_total_lag_1d": 127,
        "usage_lag_1d": 12.3,
        "usage_lag_7d": 11.8,
        "rolling_usage_last_7d": 12.1,
        "usage_same_weekday_lag_28d": 11.5
      }
    }
  ]
}
```

#### Response Example

```json
{
  "predictions": [
    {
      "sku": "BEANS-ESP-1KG",
      "date": "2025-09-01",
      "predicted_usage": 8.2,
      "confidence": 0.85,
      "factors": {
        "temporal": 0.3,
        "historical": 0.4,
        "volume": 0.2,
        "trend": 0.1
      },
      "recommendations": {
        "reorder_quantity": 15.0,
        "safety_stock": 2.0,
        "reorder_point": 5.0
      }
    },
    {
      "sku": "DAIRY-MILK-1L",
      "date": "2025-09-01",
      "predicted_usage": 12.5,
      "confidence": 0.82,
      "factors": {
        "temporal": 0.25,
        "historical": 0.45,
        "volume": 0.2,
        "trend": 0.1
      },
      "recommendations": {
        "reorder_quantity": 20.0,
        "safety_stock": 3.0,
        "reorder_point": 8.0
      }
    }
  ],
  "metadata": {
    "model_version": "1.0.0",
    "prediction_timestamp": "2025-09-01T12:00:00Z",
    "processing_time_ms": 120,
    "total_predictions": 2
  }
}
```

#### Implementation Examples

**Swift:**
```swift
struct BatchPredictionRequest: Codable {
    let predictions: [PredictionRequest]
}

struct BatchPredictionResponse: Codable {
    let predictions: [UsagePrediction]
    let metadata: PredictionMetadata
}

let batchRequest = BatchPredictionRequest(predictions: [
    PredictionRequest(sku: "BEANS-ESP-1KG", date: "2025-09-01", features: features1),
    PredictionRequest(sku: "DAIRY-MILK-1L", date: "2025-09-01", features: features2)
])

let requestData = try JSONEncoder().encode(batchRequest)
let response: BatchPredictionResponse = try await api.makeRequest(
    endpoint: "/predictions/usage/batch",
    method: "POST",
    body: requestData
)

for prediction in response.predictions {
    print("\(prediction.sku): \(prediction.predictedUsage) (confidence: \(prediction.confidence))")
}
```

**Python:**
```python
batch_data = {
    "predictions": [
        {
            "sku": "BEANS-ESP-1KG",
            "date": "2025-09-01",
            "features": features1
        },
        {
            "sku": "DAIRY-MILK-1L",
            "date": "2025-09-01",
            "features": features2
        }
    ]
}

response = api.make_request("/predictions/usage/batch", method="POST", data=batch_data)

for prediction in response['predictions']:
    print(f"{prediction['sku']}: {prediction['predicted_usage']} (confidence: {prediction['confidence']})")
```

---

## Tutorial: Historical Predictions

### Step 6: Analyzing Past Predictions

You can retrieve historical predictions to analyze model performance and trends.

#### Historical Predictions Endpoint

```http
GET /api/predictions/history?sku={sku}&start_date={start_date}&end_date={end_date}
```

#### Request Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `sku` | string | Yes | Stock keeping unit identifier |
| `start_date` | string | Yes | Start date (YYYY-MM-DD) |
| `end_date` | string | Yes | End date (YYYY-MM-DD) |
| `limit` | integer | No | Maximum number of records (default: 100) |
| `offset` | integer | No | Number of records to skip (default: 0) |

#### Response Example

```json
{
  "predictions": [
    {
      "sku": "BEANS-ESP-1KG",
      "date": "2025-08-30",
      "predicted_usage": 7.8,
      "actual_usage": 8.1,
      "accuracy": 0.96,
      "confidence": 0.83,
      "error": 0.3
    },
    {
      "sku": "BEANS-ESP-1KG",
      "date": "2025-08-31",
      "predicted_usage": 8.2,
      "actual_usage": 8.0,
      "accuracy": 0.98,
      "confidence": 0.85,
      "error": -0.2
    }
  ],
  "summary": {
    "total_predictions": 2,
    "average_accuracy": 0.97,
    "average_error": 0.05,
    "model_performance": "excellent"
  },
  "metadata": {
    "query_timestamp": "2025-09-01T12:00:00Z",
    "processing_time_ms": 25
  }
}
```

#### Implementation Examples

**Swift:**
```swift
struct HistoricalPrediction: Codable {
    let sku: String
    let date: String
    let predictedUsage: Double
    let actualUsage: Double
    let accuracy: Double
    let confidence: Double
    let error: Double
}

struct HistoricalResponse: Codable {
    let predictions: [HistoricalPrediction]
    let summary: PerformanceSummary
    let metadata: QueryMetadata
}

struct PerformanceSummary: Codable {
    let totalPredictions: Int
    let averageAccuracy: Double
    let averageError: Double
    let modelPerformance: String
}

let history: HistoricalResponse = try await api.makeRequest(
    endpoint: "/predictions/history?sku=BEANS-ESP-1KG&start_date=2025-08-30&end_date=2025-08-31"
)

print("Average Accuracy: \(history.summary.averageAccuracy)")
for prediction in history.predictions {
    print("\(prediction.date): Predicted \(prediction.predictedUsage), Actual \(prediction.actualUsage)")
}
```

**Python:**
```python
params = {
    "sku": "BEANS-ESP-1KG",
    "start_date": "2025-08-30",
    "end_date": "2025-08-31"
}

response = api.make_request("/predictions/history", params=params)
print(f"Average Accuracy: {response['summary']['average_accuracy']}")

for prediction in response['predictions']:
    print(f"{prediction['date']}: Predicted {prediction['predicted_usage']}, Actual {prediction['actual_usage']}")
```

---

## Tutorial: Error Handling

### Step 7: Handling API Errors

Proper error handling is crucial for production applications.

#### Common Error Responses

**Authentication Error (401):**
```json
{
  "error": "unauthorized",
  "message": "Invalid or missing API key",
  "timestamp": "2025-09-01T12:00:00Z"
}
```

**Validation Error (400):**
```json
{
  "error": "validation_error",
  "message": "Invalid input parameters",
  "details": {
    "sku": "SKU is required",
    "features.usage_lag_1d": "Must be a positive number"
  },
  "timestamp": "2025-09-01T12:00:00Z"
}
```

**Server Error (500):**
```json
{
  "error": "internal_server_error",
  "message": "An unexpected error occurred",
  "timestamp": "2025-09-01T12:00:00Z"
}
```

#### Implementation Examples

**Swift:**
```swift
enum APIError: Error {
    case unauthorized
    case validationError([String: String])
    case serverError
    case networkError(Error)
}

do {
    let prediction: PredictionResponse = try await api.makeRequest(
        endpoint: "/predictions/usage",
        method: "POST",
        body: requestData
    )
    // Handle successful response
} catch APIError.unauthorized {
    print("Authentication failed. Check your API key.")
} catch APIError.validationError(let details) {
    print("Validation errors: \(details)")
} catch APIError.serverError {
    print("Server error. Please try again later.")
} catch {
    print("Unexpected error: \(error)")
}
```

**Python:**
```python
try:
    response = api.make_request("/predictions/usage", method="POST", data=prediction_data)
    # Handle successful response
except requests.exceptions.HTTPError as e:
    if e.response.status_code == 401:
        print("Authentication failed. Check your API key.")
    elif e.response.status_code == 400:
        error_data = e.response.json()
        print(f"Validation errors: {error_data.get('details', {})}")
    elif e.response.status_code == 500:
        print("Server error. Please try again later.")
    else:
        print(f"HTTP error: {e.response.status_code}")
except requests.exceptions.RequestException as e:
    print(f"Network error: {e}")
```

---

## Tutorial: Real-World Integration

### Step 8: Building a Complete Application

Let's build a complete example that integrates predictions into a cafe management system.

#### Complete Swift Example

```swift
import Foundation

class CafeInventoryManager {
    private let api: CafeSmartAPI
    private let inventory: [String: Double] = [
        "BEANS-ESP-1KG": 12.5,
        "DAIRY-MILK-1L": 8.0,
        "BAKERY-DOUGH-CROIS": 25.0
    ]
    
    init(apiKey: String) {
        self.api = CafeSmartAPI(apiKey: apiKey)
    }
    
    func generateInventoryReport() async throws -> InventoryReport {
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: today)
        
        // Get predictions for all inventory items
        var predictions: [String: UsagePrediction] = [:]
        
        for sku in inventory.keys {
            let features = try await getFeaturesForSKU(sku, date: today)
            let request = PredictionRequest(sku: sku, date: dateString, features: features)
            let requestData = try JSONEncoder().encode(request)
            
            let response: PredictionResponse = try await api.makeRequest(
                endpoint: "/predictions/usage",
                method: "POST",
                body: requestData
            )
            
            predictions[sku] = response.prediction
        }
        
        // Generate recommendations
        var recommendations: [InventoryRecommendation] = []
        
        for (sku, prediction) in predictions {
            let currentStock = inventory[sku] ?? 0
            let recommendation = generateRecommendation(
                sku: sku,
                currentStock: currentStock,
                prediction: prediction
            )
            recommendations.append(recommendation)
        }
        
        return InventoryReport(
            date: dateString,
            predictions: predictions,
            recommendations: recommendations
        )
    }
    
    private func getFeaturesForSKU(_ sku: String, date: Date) async throws -> UsageFeatures {
        // In a real application, you would fetch this data from your database
        // For this example, we'll use mock data
        return UsageFeatures(
            year: 2025,
            month: 9,
            day: 1,
            weekday: 2,
            isWeekend: false,
            ordersTotalLag1d: 45,
            itemsTotalLag1d: 127,
            usageLag1d: 8.5,
            usageLag7d: 7.2,
            rollingUsageLast7d: 7.8,
            usageSameWeekdayLag28d: 6.9
        )
    }
    
    private func generateRecommendation(
        sku: String,
        currentStock: Double,
        prediction: UsagePrediction
    ) -> InventoryRecommendation {
        let daysUntilReorder = currentStock / prediction.predictedUsage
        let needsReorder = daysUntilReorder <= prediction.recommendations.reorderPoint
        
        return InventoryRecommendation(
            sku: sku,
            currentStock: currentStock,
            predictedUsage: prediction.predictedUsage,
            daysUntilReorder: daysUntilReorder,
            needsReorder: needsReorder,
            recommendedOrderQuantity: prediction.recommendations.reorderQuantity,
            confidence: prediction.confidence
        )
    }
}

struct InventoryReport {
    let date: String
    let predictions: [String: UsagePrediction]
    let recommendations: [InventoryRecommendation]
}

struct InventoryRecommendation {
    let sku: String
    let currentStock: Double
    let predictedUsage: Double
    let daysUntilReorder: Double
    let needsReorder: Bool
    let recommendedOrderQuantity: Double
    let confidence: Double
}

// Usage
let manager = CafeInventoryManager(apiKey: "YOUR_API_KEY")

do {
    let report = try await manager.generateInventoryReport()
    
    print("Inventory Report for \(report.date)")
    print("=" * 50)
    
    for recommendation in report.recommendations {
        print("SKU: \(recommendation.sku)")
        print("  Current Stock: \(recommendation.currentStock)")
        print("  Predicted Usage: \(recommendation.predictedUsage)")
        print("  Days Until Reorder: \(recommendation.daysUntilReorder)")
        print("  Needs Reorder: \(recommendation.needsReorder ? "YES" : "NO")")
        print("  Recommended Order: \(recommendation.recommendedOrderQuantity)")
        print("  Confidence: \(recommendation.confidence)")
        print()
    }
} catch {
    print("Error generating report: \(error)")
}
```

#### Complete Python Example

```python
import requests
from datetime import datetime, timedelta
from typing import Dict, List

class CafeInventoryManager:
    def __init__(self, api_key: str):
        self.api = CafeSmartAPI(api_key)
        self.inventory = {
            "BEANS-ESP-1KG": 12.5,
            "DAIRY-MILK-1L": 8.0,
            "BAKERY-DOUGH-CROIS": 25.0
        }
    
    def generate_inventory_report(self) -> Dict:
        today = datetime.now()
        date_string = today.strftime("%Y-%m-%d")
        
        # Get predictions for all inventory items
        predictions = {}
        
        for sku in self.inventory.keys():
            features = self.get_features_for_sku(sku, today)
            prediction_data = {
                "sku": sku,
                "date": date_string,
                "features": features
            }
            
            response = self.api.make_request("/predictions/usage", method="POST", data=prediction_data)
            predictions[sku] = response["prediction"]
        
        # Generate recommendations
        recommendations = []
        
        for sku, prediction in predictions.items():
            current_stock = self.inventory.get(sku, 0)
            recommendation = self.generate_recommendation(sku, current_stock, prediction)
            recommendations.append(recommendation)
        
        return {
            "date": date_string,
            "predictions": predictions,
            "recommendations": recommendations
        }
    
    def get_features_for_sku(self, sku: str, date: datetime) -> Dict:
        # In a real application, you would fetch this data from your database
        # For this example, we'll use mock data
        return {
            "year": 2025,
            "month": 9,
            "day": 1,
            "weekday": 2,
            "is_weekend": False,
            "orders_total_lag_1d": 45,
            "items_total_lag_1d": 127,
            "usage_lag_1d": 8.5,
            "usage_lag_7d": 7.2,
            "rolling_usage_last_7d": 7.8,
            "usage_same_weekday_lag_28d": 6.9
        }
    
    def generate_recommendation(self, sku: str, current_stock: float, prediction: Dict) -> Dict:
        days_until_reorder = current_stock / prediction["predicted_usage"]
        needs_reorder = days_until_reorder <= prediction["recommendations"]["reorder_point"]
        
        return {
            "sku": sku,
            "current_stock": current_stock,
            "predicted_usage": prediction["predicted_usage"],
            "days_until_reorder": days_until_reorder,
            "needs_reorder": needs_reorder,
            "recommended_order_quantity": prediction["recommendations"]["reorder_quantity"],
            "confidence": prediction["confidence"]
        }

# Usage
manager = CafeInventoryManager("YOUR_API_KEY")

try:
    report = manager.generate_inventory_report()
    
    print(f"Inventory Report for {report['date']}")
    print("=" * 50)
    
    for recommendation in report["recommendations"]:
        print(f"SKU: {recommendation['sku']}")
        print(f"  Current Stock: {recommendation['current_stock']}")
        print(f"  Predicted Usage: {recommendation['predicted_usage']}")
        print(f"  Days Until Reorder: {recommendation['days_until_reorder']:.1f}")
        print(f"  Needs Reorder: {'YES' if recommendation['needs_reorder'] else 'NO'}")
        print(f"  Recommended Order: {recommendation['recommended_order_quantity']}")
        print(f"  Confidence: {recommendation['confidence']}")
        print()

except Exception as e:
    print(f"Error generating report: {e}")
```

---

## Tutorial: Monitoring and Analytics

### Step 9: Tracking Prediction Performance

Monitoring prediction accuracy helps you understand model performance and make improvements.

#### Performance Metrics Endpoint

```http
GET /api/analytics/performance?sku={sku}&start_date={start_date}&end_date={end_date}
```

#### Response Example

```json
{
  "metrics": {
    "total_predictions": 30,
    "average_accuracy": 0.94,
    "mean_absolute_error": 0.15,
    "root_mean_square_error": 0.22,
    "r_squared": 0.87,
    "accuracy_trend": "improving"
  },
  "daily_performance": [
    {
      "date": "2025-08-30",
      "accuracy": 0.96,
      "error": 0.12,
      "confidence": 0.85
    },
    {
      "date": "2025-08-31",
      "accuracy": 0.93,
      "error": 0.18,
      "confidence": 0.82
    }
  ],
  "recommendations": [
    "Model performance is excellent",
    "Consider retraining if accuracy drops below 0.90",
    "Monitor confidence scores for low-confidence predictions"
  ]
}
```

#### Implementation Example

```swift
struct PerformanceMetrics: Codable {
    let totalPredictions: Int
    let averageAccuracy: Double
    let meanAbsoluteError: Double
    let rootMeanSquareError: Double
    let rSquared: Double
    let accuracyTrend: String
}

struct PerformanceResponse: Codable {
    let metrics: PerformanceMetrics
    let dailyPerformance: [DailyPerformance]
    let recommendations: [String]
}

let performance: PerformanceResponse = try await api.makeRequest(
    endpoint: "/analytics/performance?sku=BEANS-ESP-1KG&start_date=2025-08-01&end_date=2025-08-31"
)

print("Average Accuracy: \(performance.metrics.averageAccuracy)")
print("Trend: \(performance.metrics.accuracyTrend)")

for recommendation in performance.recommendations {
    print("• \(recommendation)")
}
```

---

## 🎯 **Hands-On Exercises**

### **Exercise 1: Your First Prediction**
**Goal**: Make a prediction for tomorrow's coffee bean usage

**Your Task:**
1. Set up the API client (choose Swift, Python, or cURL)
2. Create a prediction request for "BEANS-ESP-1KG" for tomorrow
3. Handle the response and extract the predicted usage
4. Calculate how many days of stock you have left

**Expected Output:**
```
SKU: BEANS-ESP-1KG
Predicted Usage: 8.2kg
Confidence: 85%
Days of Stock Remaining: 1.8 days
```

### **Exercise 2: Batch Predictions for Inventory Planning**
**Goal**: Get predictions for all your key ingredients

**Your Task:**
1. Create a batch request for 3 different SKUs
2. Process the batch response
3. Generate a reorder recommendation report
4. Handle any errors gracefully

**SKUs to Use:**
- "BEANS-ESP-1KG" (Coffee beans)
- "DAIRY-MILK-1L" (Milk)
- "BAKERY-DOUGH-CROIS" (Croissant dough)

### **Exercise 3: Performance Analysis**
**Goal**: Analyze your model's accuracy over time

**Your Task:**
1. Retrieve historical predictions for the last 7 days
2. Calculate the average accuracy
3. Identify any patterns in prediction errors
4. Generate a performance report

### **Exercise 4: Real-World Integration**
**Goal**: Build a complete inventory management system

**Your Task:**
1. Create a class/function that manages your cafe's inventory
2. Integrate predictions into your reorder logic
3. Add error handling and logging
4. Test with different scenarios (low stock, high demand, etc.)

## 🧠 **Knowledge Check**

### **Technical Questions:**
1. What's the difference between a single prediction and a batch prediction?
2. How do you handle authentication errors in your API client?
3. What information does the confidence score provide?
4. How would you implement retry logic for failed API calls?

### **Business Questions:**
5. **Scenario**: Your model predicts 12.5L milk usage tomorrow with 82% confidence. You have 8L in stock. Your supplier delivers in 2 days. What should you do?

6. **Decision Making**: The API returns a prediction with 45% confidence. How does this affect your inventory decisions?

7. **Optimization**: You're running predictions for 50 different SKUs daily. How would you optimize this for performance and cost?

## 🚀 **Advanced Challenges**

### **Challenge 1: Multi-Location Support**
Extend your inventory manager to handle multiple cafe locations with different patterns.

### **Challenge 2: Automated Alerts**
Build a system that automatically sends alerts when:
- Stock levels are predicted to run out
- Predictions have low confidence
- Unusual usage patterns are detected

### **Challenge 3: Performance Monitoring**
Create a dashboard that tracks:
- Model accuracy over time
- API response times
- Prediction confidence trends
- Business impact of predictions

## 📊 **Real-World Application Project**

### **Project: Smart Inventory Manager**

**Objective**: Build a complete inventory management system using the Predictions API

**Requirements:**
1. **Daily Predictions**: Automatically predict usage for all SKUs
2. **Reorder Logic**: Automatically generate reorder recommendations
3. **Alert System**: Notify managers of critical stock levels
4. **Performance Tracking**: Monitor prediction accuracy and business impact
5. **Reporting**: Generate weekly inventory reports

**Deliverables:**
- Working application with source code
- Documentation explaining your approach
- Performance metrics and business impact analysis
- Recommendations for improvement

**Success Criteria:**
- Reduces stockouts by 80%
- Reduces waste by 30%
- Provides actionable insights to managers
- Handles errors gracefully

## 📚 **Additional Resources**

### **API Documentation:**
- **Complete API Reference**: All endpoints and parameters
- **Error Codes**: Comprehensive error handling guide
- **Rate Limits**: Understanding API usage limits
- **Best Practices**: Performance optimization tips

### **Integration Examples:**
- **Web Dashboard**: Building a web interface for predictions
- **Mobile App**: Integrating predictions into a mobile app
- **Database Integration**: Storing predictions and historical data
- **Third-party Tools**: Connecting with existing business tools

### **Advanced Topics:**
- **Model Retraining**: When and how to retrain your models
- **A/B Testing**: Testing different prediction strategies
- **Cost Optimization**: Minimizing API costs while maintaining accuracy
- **Scaling**: Handling high-volume prediction requests

## 🎓 **Learning Outcomes**

**By completing this tutorial and exercises, you will:**

✅ **Master** the CafeSmart Predictions API  
✅ **Build** production-ready applications with ML predictions  
✅ **Handle** errors and edge cases professionally  
✅ **Optimize** API usage for performance and cost  
✅ **Integrate** predictions into real business workflows  
✅ **Monitor** model performance and business impact  
✅ **Scale** applications to handle multiple locations  
✅ **Design** robust systems with proper error handling  

**You're now ready to build intelligent, data-driven cafe management systems!**

---

*This tutorial provides comprehensive, hands-on experience with the CafeSmart ML Predictions API. The exercises and challenges ensure you can apply these skills to real-world business problems.*

# CafeSmart ML Documentation

Learn how to build intelligent cafe management systems using machine learning and business intelligence.

## Overview

CafeSmart ML is a comprehensive machine learning system designed to optimize cafe operations through intelligent inventory management, demand forecasting, and business intelligence insights.

## Topics

### Tutorials

- <doc:PredictionsAPITutorial> - Using the CafeSmart ML Predictions API
- <doc:CafeSmartMLTutorial> - Business Intelligence & Feature Engineering

### Articles

- <doc:MLPredictions> - Understanding ML Predictions
- <doc:CoreMLIntegration> - Core ML Integration Guide

## Getting Started

To get started with CafeSmart ML:

1. **Learn the API**: Follow the <doc:PredictionsAPITutorial> to understand how to use the predictions API
2. **Understand the concepts**: Read the <doc:CafeSmartMLTutorial> to learn about business intelligence
3. **Explore technical details**: Check the <doc:MLPredictions> article for prediction insights
4. **Integrate with iOS**: Follow the <doc:CoreMLIntegration> guide for technical implementation

## System Architecture

CafeSmart ML consists of several key components:

- **Predictions API**: RESTful endpoints for real-time predictions
- **Business Intelligence Layer**: Understanding cafe operations and data patterns
- **Feature Engineering Pipeline**: Transforming raw data into ML features
- **Prediction Models**: Core ML models for demand forecasting
- **Monitoring & Analytics**: Performance tracking and insights

## Key Features

- **Intelligent Inventory Management**: Predict ingredient usage to prevent stockouts
- **Demand Forecasting**: Anticipate customer demand patterns
- **Business Intelligence**: Convert data into actionable insights
- **Real-time Predictions**: Get instant recommendations via API
- **Performance Monitoring**: Track model accuracy and business impact

## API Quick Start

### Authentication
```http
Authorization: Bearer YOUR_API_KEY
```

### Make a Prediction
```bash
curl -X POST \
     -H "Authorization: Bearer YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"sku": "BEANS-ESP-1KG", "date": "2025-09-01", "features": {...}}' \
     https://your-cafesmart-api.com/api/predictions/usage
```

### Check API Health
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     https://your-cafesmart-api.com/api/health
```

## Learning Path

### For API Users
1. **Start with**: <doc:PredictionsAPITutorial> - Complete API tutorial
2. **Learn concepts**: <doc:CafeSmartMLTutorial> - Business intelligence
3. **Understand predictions**: <doc:MLPredictions> - How predictions work
4. **Integrate**: <doc:CoreMLIntegration> - iOS implementation

### For Developers
1. **API Integration**: <doc:PredictionsAPITutorial> - REST API usage
2. **Business Logic**: <doc:CafeSmartMLTutorial> - Feature engineering
3. **Technical Details**: <doc:MLPredictions> - Model architecture
4. **Platform Integration**: <doc:CoreMLIntegration> - Core ML setup

---

*CafeSmart ML transforms cafe operations through intelligent machine learning and business intelligence.*

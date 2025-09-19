import XCTest
@testable import CafeSmartMLTutorial

final class CafeSmartMLTutorialTests: XCTestCase {
    
    func testCafeSmartMLInitialization() {
        let cafeSmart = CafeSmartML()
        XCTAssertNotNil(cafeSmart)
    }
    
    func testUsageFeaturesInitialization() {
        let features = UsageFeatures(
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
        
        XCTAssertEqual(features.year, 2025)
        XCTAssertEqual(features.month, 9)
        XCTAssertEqual(features.day, 1)
        XCTAssertEqual(features.weekday, 2)
        XCTAssertFalse(features.isWeekend)
        XCTAssertEqual(features.ordersTotalLag1d, 45)
        XCTAssertEqual(features.itemsTotalLag1d, 127)
        XCTAssertEqual(features.usageLag1d, 8.5, accuracy: 0.01)
        XCTAssertEqual(features.usageLag7d, 7.2, accuracy: 0.01)
        XCTAssertEqual(features.rollingUsageLast7d, 7.8, accuracy: 0.01)
        XCTAssertEqual(features.usageSameWeekdayLag28d, 6.9, accuracy: 0.01)
    }
    
    func testUsagePredictionInitialization() {
        let date = Date()
        let prediction = UsagePrediction(
            sku: "BEANS-ESP-1KG",
            date: date,
            predictedUsage: 8.2,
            confidence: 0.85
        )
        
        XCTAssertEqual(prediction.sku, "BEANS-ESP-1KG")
        XCTAssertEqual(prediction.date, date)
        XCTAssertEqual(prediction.predictedUsage, 8.2, accuracy: 0.01)
        XCTAssertEqual(prediction.confidence, 0.85, accuracy: 0.01)
    }
    
    func testPredictionErrorCases() {
        let modelNotFound = PredictionError.modelNotFound
        let invalidInput = PredictionError.invalidInput
        let predictionFailed = PredictionError.predictionFailed(NSError(domain: "test", code: 1))
        let unsupportedSKU = PredictionError.unsupportedSKU("INVALID-SKU")
        
        XCTAssertNotNil(modelNotFound)
        XCTAssertNotNil(invalidInput)
        XCTAssertNotNil(predictionFailed)
        XCTAssertNotNil(unsupportedSKU)
    }
    
    func testCafeSmartMLVersion() {
        XCTAssertEqual(CafeSmartML.version, "1.0.0")
    }
    
    func testUsagePredictionWithCafeSmartML() throws {
        let cafeSmart = CafeSmartML()
        let features = UsageFeatures(
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
        
        let prediction = try cafeSmart.predictUsage(
            for: "BEANS-ESP-1KG",
            date: Date(),
            features: features
        )
        
        XCTAssertEqual(prediction.sku, "BEANS-ESP-1KG")
        XCTAssertGreaterThan(prediction.predictedUsage, 0)
        XCTAssertGreaterThanOrEqual(prediction.confidence, 0)
        XCTAssertLessThanOrEqual(prediction.confidence, 1)
    }
}

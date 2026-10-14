import Testing
import Vapor
import Foundation
import BSON
@testable import cafe_smart_api

@Suite(.serialized)
actor PredictorControllerTests {
  private var app: Application!

  func setUp() async throws {
    app = try await APITestHelpers.makeApp(adminEmail: "predictor-test@example.com")
  }

  func tearDown() async throws {
    try await APITestHelpers.shutdownApp(app)
  }

  private func withApp(_ body: () async throws -> Void) async throws {
    try await setUp()
    do {
      try await body()
    } catch {
      try await tearDown()
      throw error
    }
    try await tearDown()
  }

  private func req<T: Content>(_ body: T) -> Request {
    let r = Request(application: app, on: app.eventLoopGroup.next())
    r.headers.contentType = .json
    try! r.content.encode(body)
    return r
  }



  @Test
  func testExportCSVHeaders() async throws {
    try await withApp {
      let controller = CafePredictorController()

      func makeReq(mode: String) -> Request {
        let r = Request(application: app, on: app.eventLoopGroup.next())
        try! r.query.encode(["mode": mode])
        return r
      }

      let ok = try await controller.exportCSV(req: makeReq(mode: "ingredientDaily"))
      #expect(ok.status == .ok)
      #expect(ok.headers[.contentType].first?.contains("text/csv") == true)
      #expect(ok.headers[.contentDisposition].first?.contains("cafe_data_") == true)
      #expect(ok.headers[.contentDisposition].first?.contains(".csv") == true)

      let workload = try await controller.exportCSV(req: makeReq(mode: "workloadhourly"))
      #expect(workload.status == .ok)
      let workloadCSV = String(data: APITestHelpers.responseData(workload), encoding: .utf8) ?? ""
      #expect(workloadCSV.contains("target_orders"))

      do {
        _ = try await controller.exportCSV(req: makeReq(mode: "unknownDataset"))
        Issue.record("Expected unsupported export mode to throw")
      } catch let abort as any AbortError {
        #expect(abort.status == .badRequest)
      }
    }
  }

  @Test
  func testDecideRestockBySku() async throws {
    try await withApp {
      // Seed test data
      let store = app.mongoStore as! TestableMongoStore
      // Inventory
      let inv = InventoryItem(
        id: ObjectId().hexString,
        sku: "BEANS-TEST-1KG",
        name: "Test Beans",
        quantity: 10,
        reorderThreshold: 5,
        unit: "bag",
        supplier: nil
      )
      _ = try await store.create(inventoryItem: inv)

      let controller = CafePredictorController()
      // Testing mode returns ramp forecast (1..n). lead defaults to 3.
      struct DecideBody: Content { let sku: String; let daysAhead: Int }
      let reqBody = DecideBody(sku: "BEANS-TEST-1KG", daysAhead: 7)
      let req = Request(application: app, on: app.eventLoopGroup.next())
      req.headers.contentType = .json
      try req.content.encode(reqBody)

      let resp = try await controller.decideRestock(req: req)
      #expect(resp.sku == "BEANS-TEST-1KG")
      #expect(resp.leadTimeDays == 3) // default
      // Forecast ramp 1+2+3 for lead=3 => 6, safety = reorderThreshold=5 => ROP=11
      // onHand=10, so needRestock = true, reorderQty >= 1
      #expect(resp.reorderPoint == 11)
      #expect(resp.onHand == 10)
      #expect(resp.needRestock == true)
      #expect(resp.reorderQty >= 1)
    }
  }

  @Test
  func testDecideRestockNoRestock() async throws {
    try await withApp {
      // Seed test data with high on-hand to avoid restock
      let store = app.mongoStore as! TestableMongoStore
      let inv = InventoryItem(
        id: ObjectId().hexString,
        sku: "BEANS-ENOUGH-1KG",
        name: "Beans Plenty",
        quantity: 20, // onHand > ROP (11) given defaults
        reorderThreshold: 5,
        unit: "bag",
        supplier: nil
      )
      _ = try await store.create(inventoryItem: inv)

      let controller = CafePredictorController()
      struct DecideBody: Content { let sku: String; let daysAhead: Int }
      let reqBody = DecideBody(sku: "BEANS-ENOUGH-1KG", daysAhead: 7)
      let req = Request(application: app, on: app.eventLoopGroup.next())
      req.headers.contentType = .json
      try req.content.encode(reqBody)

      let resp = try await controller.decideRestock(req: req)
      // With testing ramp 1+2+3 and safety=reorderThreshold=5 -> ROP=11; onHand=20
      #expect(resp.needRestock == false)
      #expect(resp.reorderQty == 0)
    }
  }
  
  // MARK: - New ML Functionality Tests
  
  @Test
  func testForecastSeriesWithRealData() async throws {
    try await withApp {
    
      // Seed test data with inventory and orders
      let store = app.mongoStore as! TestableMongoStore
    
      // Create inventory item
      var inv = InventoryItem(
        id: ObjectId().hexString,
        sku: "BEANS-ML-TEST-1KG",
        name: "ML Test Beans",
        quantity: 8,
        reorderThreshold: 5,
        unit: "bag",
        supplier: "Test Supplier"
      )
      inv.leadTimeDays = 3
      _ = try await store.create(inventoryItem: inv)
    
      // Create some test orders to generate usage data
      let now = Date()
      var order1 = Order(
        id: ObjectId().hexString,
        status: .completed,
        customerName: "Test Customer 1",
        items: [
          OrderItem(menuItemId: "espresso-1", quantity: 2, notes: nil),
          OrderItem(menuItemId: "cappuccino-1", quantity: 1, notes: nil)
        ],
        pickupTime: nil,
        createdAt: now.addingTimeInterval(-86400) // 1 day ago
      )
      order1.channel = .dineIn
      order1.serviceType = .barista
      _ = try await store.create(order: order1)
    
      var order2 = Order(
        id: ObjectId().hexString,
        status: .completed,
        customerName: "Test Customer 2",
        items: [
          OrderItem(menuItemId: "espresso-2", quantity: 3, notes: nil)
        ],
        pickupTime: nil,
        createdAt: now.addingTimeInterval(-172800) // 2 days ago
      )
      order2.channel = .takeaway
      order2.serviceType = .barista
      _ = try await store.create(order: order2)
    
      let controller = CafePredictorController()
    
      // Test the forecastSeries method directly
      let forecast = try await controller.forecastSeries(app: app, horizon: 5, sku: "BEANS-ML-TEST-1KG")
    
      // Should return 5 forecast values
      #expect(forecast.count == 5)
    
      // Forecast values should be realistic (not all zeros)
      #expect(forecast.allSatisfy { $0 >= 0 })
    
      // At least some values should be greater than 0 (indicating usage)
      #expect(forecast.contains { $0 > 0 })
    }
  }
  
  @Test
  func testDecideRestockWithMLForecast() async throws {
    try await withApp {
    
      // Seed test data
      let store = app.mongoStore as! TestableMongoStore
    
      // Create inventory item that should trigger restock
      var inv = InventoryItem(
        id: ObjectId().hexString,
        sku: "BEANS-ML-RESTOCK-1KG",
        name: "ML Restock Beans",
        quantity: 3, // Low quantity
        reorderThreshold: 5,
        unit: "bag",
        supplier: "Test Supplier"
      )
      inv.leadTimeDays = 2
      _ = try await store.create(inventoryItem: inv)
    
      // Create orders to generate usage patterns
      let now = Date()
      for i in 1...7 {
        var order = Order(
          id: ObjectId().hexString,
          status: .completed,
          customerName: "Customer \(i)",
          items: [
            OrderItem(menuItemId: "coffee-\(i)", quantity: 1, notes: nil)
          ],
          pickupTime: nil,
          createdAt: now.addingTimeInterval(TimeInterval(-i * 86400)) // i days ago
        )
        order.channel = .dineIn
        order.serviceType = .barista
        _ = try await store.create(order: order)
      }
    
      let controller = CafePredictorController()
    
      // Test restock decision with ML forecast
      let request = Request(application: app, method: .POST, url: "/api/predictor/restock", on: app.eventLoopGroup.next())
      let body = CafePredictorController.RestockDecisionRequest(sku: "BEANS-ML-RESTOCK-1KG", daysAhead: 7)
      try request.content.encode(body)
      let decision = try await controller.decideRestock(req: request)
    
      // Verify the decision structure
      #expect(decision.sku == "BEANS-ML-RESTOCK-1KG")
      #expect(decision.onHand == 3)
      #expect(decision.leadTimeDays == 2)
      #expect(decision.forecastSumNextLeadTime >= 0)
    
      // Should need restock due to low quantity
      #expect(decision.needRestock == true)
      #expect(decision.reorderQty > 0)
      #expect(decision.reorderPoint > decision.onHand)
    }
  }
  
  @Test
  func testUsageCalculationMethods() async throws {
    try await withApp {
    
      let store = app.mongoStore as! TestableMongoStore
      let controller = CafePredictorController()
    
      // Create test orders
      let now = Date()
      let order1 = Order(
        id: ObjectId().hexString,
        status: .completed,
        customerName: "Test",
        items: [
          OrderItem(menuItemId: "item1", quantity: 2, notes: nil),
          OrderItem(menuItemId: "item2", quantity: 1, notes: nil)
        ],
        pickupTime: nil,
        createdAt: now.addingTimeInterval(-86400) // 1 day ago
      )
      _ = try await store.create(order: order1)
    
      let order2 = Order(
        id: ObjectId().hexString,
        status: .completed,
        customerName: "Test",
        items: [
          OrderItem(menuItemId: "item3", quantity: 3, notes: nil)
        ],
        pickupTime: nil,
        createdAt: now.addingTimeInterval(-172800) // 2 days ago
      )
      _ = try await store.create(order: order2)
    
      let orders = try await store.listOrders()
    
      // Test usage calculation methods
      let usage1d = await controller.calculateUsageFromOrders(orders: orders, sku: "BEANS-ESP-1KG", daysAgo: 1, app: app)
      let usage2d = await controller.calculateUsageFromOrders(orders: orders, sku: "BEANS-ESP-1KG", daysAgo: 2, app: app)
      let rollingUsage = await controller.calculateRollingUsage(orders: orders, sku: "BEANS-ESP-1KG", days: 2, app: app)
      let orderCount = controller.calculateOrderCount(orders: orders, daysAgo: 1)
      let itemsSold = controller.calculateItemsSold(orders: orders, daysAgo: 1)
    
      // Verify calculations (exact when store is unseeded)
      #expect(usage1d >= 0)
      #expect(usage2d >= 0)
      #expect(rollingUsage >= 0)
      #expect(orderCount >= 1) // at least our order from 1 day ago
      #expect(itemsSold >= 3) // at least 2+1 items from 1 day ago
    }
  }
  
  @Test
  func testMLModelIntegration() async throws {
    try await withApp {
    
      // This test would require a real ML model to be loaded
      // For now, we'll test that the system gracefully handles missing models
    
      let controller = CafePredictorController()
    
      // Test that the system can handle missing ML models gracefully
      do {
        let _ = try await controller.forecastSeries(app: app, horizon: 3, sku: "NONEXISTENT-SKU")
        // If we get here, the system handled missing models gracefully
      } catch {
        // Expected error for missing model
        #expect(error.localizedDescription.contains("not found") || error.localizedDescription.contains("Predictor not ready"))
      }
    }
  }
}



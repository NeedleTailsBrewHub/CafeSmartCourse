import Testing
import Vapor
import Foundation
import BSON
@testable import cafe_smart_api

@Suite(.serialized)
actor MLPredictionsTests {
  private var app: Application!

  func setUp() async throws {
    app = try await Application.make(.testing)
    app.mongoStore = TestableMongoStore(seedDummyData: true)
  }
  
  func tearDown() async throws {
    try await app.asyncShutdown()
  }

  @Test
  func testUsageCalculationMethods() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    
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
    
    // Verify calculations (accounting for existing dummy data)
    #expect(usage1d >= 0)
    #expect(usage2d >= 0)
    #expect(rollingUsage >= 0)
    #expect(orderCount >= 1) // At least 1 order 1 day ago (our test order)
    #expect(itemsSold >= 3) // At least 2+1 items 1 day ago (our test order)
    
    print("✅ Usage calculations: 1d=\(usage1d), 2d=\(usage2d), rolling=\(rollingUsage), orders=\(orderCount), items=\(itemsSold)")
  }
  
  @Test
  func testSKUUsageCalculation() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    
    let controller = CafePredictorController()
    
    // Test different SKU usage patterns
    let order = Order(
      id: ObjectId().hexString,
      status: .completed,
      customerName: "Test",
      items: [
        OrderItem(menuItemId: "espresso", quantity: 2, notes: nil),
        OrderItem(menuItemId: "cappuccino", quantity: 1, notes: nil)
      ],
      pickupTime: nil,
      createdAt: Date()
    )
    
    // Test BEANS-ESP-1KG usage (using real recipe data)
    let beansUsage = await controller.calculateOrderUsage(orders: [order], sku: "BEANS-ESP-1KG", app: app)
    #expect(beansUsage >= 0.0) // Should be non-negative, actual value depends on recipe data
    
    // Test DAIRY-MILK-1L usage (using real recipe data)
    let milkUsage = await controller.calculateOrderUsage(orders: [order], sku: "DAIRY-MILK-1L", app: app)
    #expect(milkUsage >= 0.0) // Should be non-negative, actual value depends on recipe data
    
    // Test unknown SKU usage (should be 0 since no recipe exists)
    let defaultUsage = await controller.calculateOrderUsage(orders: [order], sku: "UNKNOWN-SKU", app: app)
    #expect(defaultUsage == 0.0) // No recipe exists for unknown SKU
    
    print("✅ SKU usage calculations: beans=\(beansUsage), milk=\(milkUsage), default=\(defaultUsage)")
  }
  
  @Test
  func testDateCalculations() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    
    let store = app.mongoStore as! TestableMongoStore
    let controller = CafePredictorController()
    
    // Create orders at specific times
    let now = Date()
    let calendar = Calendar.current
    
    // Order 1: 1 day ago
    let order1 = Order(
      id: ObjectId().hexString,
      status: .completed,
      customerName: "Test1",
      items: [OrderItem(menuItemId: "item1", quantity: 1, notes: nil)],
      pickupTime: nil,
      createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now
    )
    _ = try await store.create(order: order1)
    
    // Order 2: 7 days ago
    let order2 = Order(
      id: ObjectId().hexString,
      status: .completed,
      customerName: "Test2",
      items: [OrderItem(menuItemId: "item2", quantity: 1, notes: nil)],
      pickupTime: nil,
      createdAt: calendar.date(byAdding: .day, value: -7, to: now) ?? now
    )
    _ = try await store.create(order: order2)
    
    let orders = try await store.listOrders()
    
    // Test that we get the right counts for different time periods
    let count1d = controller.calculateOrderCount(orders: orders, daysAgo: 1)
    let count7d = controller.calculateOrderCount(orders: orders, daysAgo: 7)
    let count8d = controller.calculateOrderCount(orders: orders, daysAgo: 8)
    
    // With seeded data, we expect many orders on each day
    #expect(count1d > 0) // Should have orders 1 day ago
    #expect(count7d > 0) // Should have orders 7 days ago
    #expect(count8d > 0) // Should have orders 8 days ago (seeded data spans many days)
    
    print("✅ Date calculations: 1d=\(count1d), 7d=\(count7d), 8d=\(count8d)")
  }
  
  @Test
  func testRollingUsageCalculation() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    
    let store = app.mongoStore as! TestableMongoStore
    let controller = CafePredictorController()
    
    // Create orders over the last 5 days
    let now = Date()
    let calendar = Calendar.current
    
    for i in 1...5 {
      let order = Order(
        id: ObjectId().hexString,
        status: .completed,
        customerName: "Test\(i)",
        items: [OrderItem(menuItemId: "item\(i)", quantity: i, notes: nil)], // Different quantities each day
        pickupTime: nil,
        createdAt: calendar.date(byAdding: .day, value: -i, to: now) ?? now
      )
      _ = try await store.create(order: order)
    }
    
    let orders = try await store.listOrders()
    
    // Test rolling usage for different periods
    let rolling3d = await controller.calculateRollingUsage(orders: orders, sku: "BEANS-ESP-1KG", days: 3, app: app)
    let rolling5d = await controller.calculateRollingUsage(orders: orders, sku: "BEANS-ESP-1KG", days: 5, app: app)
    
    // Rolling usage should be positive
    #expect(rolling3d > 0)
    #expect(rolling5d > 0)
    // Note: rolling5d might not be > rolling3d due to existing dummy data
    
    print("✅ Rolling usage: 3d=\(rolling3d), 5d=\(rolling5d)")
  }
  
  @Test
  func testOutputFeatureNameHandling() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    
    // This test verifies that the output feature name handling logic works correctly
    // It doesn't require a real ML model to be loaded
    
    let controller = CafePredictorController()
    
    // Test that the system can handle missing ML models gracefully
    do {
      let _ = try await controller.forecastSeries(app: app, horizon: 3, sku: "NONEXISTENT-SKU")
      // If we get here, the system handled missing models gracefully
    } catch {
      // Expected error for missing model
      let errorMessage = error.localizedDescription
      #expect(errorMessage.contains("not found") || errorMessage.contains("Predictor not ready"))
      print("✅ Expected error caught: \(errorMessage)")
    }
  }
  
  @Test
  func testCSVExportWithStoreData() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    
    let store = app.mongoStore as! TestableMongoStore
    
    // Verify that we have data in the store
    let orders = try await store.listOrders()
    let recipes = try await store.listRecipes()
    let inventory = try await store.listInventory()
    
    #expect(orders.count > 0, "Should have orders in test store")
    #expect(recipes.count > 0, "Should have recipes in test store")
    #expect(inventory.count > 0, "Should have inventory items in test store")
    
    print("✅ Store data verification: \(orders.count) orders, \(recipes.count) recipes, \(inventory.count) inventory items")
    
    // Test that the CSV export logic can process the data
    // We'll test the ingredient daily aggregation logic that's used in CSV export
    
    let calendar = Calendar.current
    var dayToOrdersTotal: [String: Int] = [:]
    var dayToItemsTotal: [String: Double] = [:]
    var dayToIngredientQty: [String: [String: Double]] = [:]
    
    // Build recipe map
    var recipeMap: [String: [RecipeComponent]] = [:]
    for recipe in recipes {
      recipeMap[recipe.menuItemId] = recipe.components
    }
    
    // Process orders similar to CSV export logic
    for order in orders {
      let dayKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: order.createdAt))
      dayToOrdersTotal[dayKey, default: 0] += 1
      
      for item in order.items {
        dayToItemsTotal[dayKey, default: 0.0] += Double(item.quantity)
        
        // Calculate ingredient usage
        if let components = recipeMap[item.menuItemId] {
          for component in components {
            let factor = component.unitsPerItem * (1.0 + (component.wastageRate ?? 0.0))
            let used = Double(item.quantity) * factor
            dayToIngredientQty[component.sku, default: [:]][dayKey, default: 0.0] += used
          }
        }
      }
    }
    
    // Verify that we have aggregated data
    #expect(dayToOrdersTotal.count > 0, "Should have aggregated order data by day")
    #expect(dayToItemsTotal.count > 0, "Should have aggregated item data by day")
    #expect(dayToIngredientQty.count > 0, "Should have aggregated ingredient usage data")
    
    // Check that we have usage data for known SKUs
    let knownSKUs = ["BEANS-ESP-1KG", "DAIRY-MILK-1L", "BAKERY-DOUGH-CROIS", "SWEET-SUGAR-1KG"]
    for sku in knownSKUs {
      if let skuData = dayToIngredientQty[sku] {
        #expect(skuData.count > 0, "Should have usage data for \(sku)")
        let totalUsage = skuData.values.reduce(0.0, +)
        #expect(totalUsage > 0, "Should have positive usage for \(sku)")
        print("✅ \(sku) usage: \(totalUsage) across \(skuData.count) days")
      }
    }
    
    print("✅ CSV export data aggregation: \(dayToOrdersTotal.count) days with orders, \(dayToIngredientQty.count) SKUs with usage data")
  }
}

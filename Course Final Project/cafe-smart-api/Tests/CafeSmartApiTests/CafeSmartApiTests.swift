@testable import CafeSmartApi
import VaporTesting
import Testing
import BinaryCodable
import BSON

@Suite("App Tests")
struct CafeSmartApiTests {
    
    private func request<T: Content>(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        data: T? = nil
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        if let token {
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.authorization, value: "Bearer \(token)")
        }
        try req.content.encode(data, as: .binaryCodable)
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }
    
    private func request(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        if let token {
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.authorization, value: "Bearer \(token)")
        }

        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        try await configure(app)
        return app
    }
    
    //Write another test that uses the access token
    
    @Test
    func testRegisterLoginAndLogout() async throws {
        
        let app = try await makeApp()
        let register = RegisterRequest(email: "Email@Test.com", password: "12345678", name: "Alice", isAdmin: true)
        let repsonse = try await request(app, .POST, "/api/register", data: register)
        let body = try repsonse.content.decode(UserPublic.self)
        #expect(body.email == "Email@Test.com".lowercased())
        #expect(body.name == "Alice")
        #expect(body.isAdmin == true)
        
        let loginRequest = LoginRequest(email: "Email@Test.com", password: "12345678")
        let loginRepsonse = try await request(app, .POST, "/api/login", data: loginRequest)
        let loginBody = try loginRepsonse.content.decode(TokenResponse.self)
        #expect(loginBody.user.email == "Email@Test.com".lowercased())
        #expect(loginBody.user.name == "Alice")
        #expect(loginBody.user.isAdmin == true)
        
        let token = loginBody.token
        let status = try await request(app, .POST, "/api/auth/logout", token: token)
        
        #expect(status.status == .ok)
        
        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
           
    }
    
    
    @Test
    func websocketConnectionTest() async throws {
        let app = try await makeApp()
        let register = RegisterRequest(email: "Email@Test.com", password: "12345678", name: "Alice", isAdmin: true)
        let repsonse = try await request(app, .POST, "/api/register", data: register)
        let body = try repsonse.content.decode(UserPublic.self)
        #expect(body.email == "Email@Test.com".lowercased())
        #expect(body.name == "Alice")
        #expect(body.isAdmin == true)
        
        let loginRequest = LoginRequest(email: "Email@Test.com", password: "12345678")
        let loginRepsonse = try await request(app, .POST, "/api/login", data: loginRequest)
        let loginBody = try loginRepsonse.content.decode(TokenResponse.self)
        #expect(loginBody.user.email == "Email@Test.com".lowercased())
        #expect(loginBody.user.name == "Alice")
        #expect(loginBody.user.isAdmin == true)
        

        
        app.http.server.configuration.port = 0
        try await app.http.server.shared.start(address: nil)
        guard let port = app.http.server.shared.localAddress?.port else {
            #expect(Bool(false), "Missing Port")
            return
        }
        

        var header = HTTPHeaders()
        header.add(name: .authorization, value: "Bearer \(loginBody.token)")
        
        let packetPromise = app.eventLoopGroup.next().makePromise(of: RealtimeHub.MessagePacket.self)
        
        try await WebSocket.connect(to: "ws://localhost:\(port)/api/auth/ws/merchant", headers: header, on: app.eventLoopGroup) { ws in
            
            
            ws.onBinary { _, buffer in
                var buffer = buffer
                if let bytes: [UInt8] = buffer.readBytes(length: buffer.readableBytes) {
                    let data = Data(bytes)
                    do {
                        let decoded = try BinaryDecoder().decode(RealtimeHub.MessagePacket.self, from: data)
                        packetPromise.succeed(decoded)
                    } catch {
                        packetPromise.fail(error)
                        print("Failed to decoded message \(error)")
                    }
                }
                try! await ws.close()
            }
        }
        
        try await Task.sleep(until: .now + .seconds(1))
        
        let order = Order(id: UUID().uuidString, status: .pending, items: [], createdAt: .init())
        let info = OrderInfo.created(order)
        
        await app.realtimeHub.publish(.order(info), to: .merchant)
        
        let received = try await packetPromise.futureResult.get()
        switch received {
        case .order(let info):
            switch info {
            case .created(let order):
                #expect(order.status == .pending)
            default:
                #expect(Bool(false), "Unexpected order info \(info)")
            }
        default:
            #expect(Bool(false), "Unexpected message \(received)")
        }
    }
    
    @Test
    func testEnhancedTestDataGeneration() async throws {
        // Create a test store with enhanced data
        let store = TestableMongoStore(seedDummyData: true)
        
        // Test inventory items
        let inventory = try await store.listInventory()
        #expect(inventory.count >= 12, "Should have at least 12 inventory items")
        
        // Verify we have the expected SKUs
        let skus = inventory.map { $0.sku }.sorted()
        let expectedSkus = [
            "BAKERY-DOUGH-BAGEL", "BAKERY-DOUGH-CROIS", "BAKERY-MUFFIN-MIX-2KG",
            "BEANS-DECAF-1KG", "BEANS-ESP-1KG", "DAIRY-CREAM-500ML",
            "DAIRY-MILK-WHOLE-1L", "DAIRY-OAT-1L", "SPICE-CINNAMON-100G",
            "SPICE-COCOA-500G", "SWEET-HONEY-500G", "SWEET-SUGAR-1KG",
            "SWEET-VANILLA-SYRUP-1L"
        ]
        
        for expectedSku in expectedSkus {
            #expect(skus.contains(expectedSku), "Missing expected SKU: \(expectedSku)")
        }
        
        // Test menu items
        let menuItems = try await store.listMenu()
        #expect(menuItems.count >= 8, "Should have at least 8 menu items")
        
        let menuNames = menuItems.map { $0.name }.sorted()
        let expectedMenuItems = [
            "Americano", "Blueberry Muffin", "Butter Croissant", "Cappuccino",
            "Espresso", "Everything Bagel", "Latte", "Mocha"
        ]
        
        for expectedName in expectedMenuItems {
            #expect(menuNames.contains(expectedName), "Missing expected menu item: \(expectedName)")
        }
        
        // Test recipes
        let recipes = try await store.listRecipes()
        #expect(recipes.count >= 8, "Should have at least 8 recipes")
        
        // Verify each menu item has a recipe
        let menuIds = Set(menuItems.map { $0.id })
        let recipeMenuIds = Set(recipes.map { $0.menuItemId })
        #expect(menuIds.isSubset(of: recipeMenuIds), "All menu items should have recipes")
        
        // Test orders
        let orders = try await store.listOrders()
        #expect(orders.count >= 1000, "Should have at least 1000 historical orders")
        
        // Verify orders span multiple days
        let orderDates = orders.map { Calendar.current.startOfDay(for: $0.createdAt) }
        let uniqueDays = Set(orderDates)
        #expect(uniqueDays.count >= 30, "Orders should span at least 30 days")
        
        // Test reservations
        let reservations = try await store.listReservations()
        #expect(reservations.count >= 100, "Should have at least 100 reservations")
        
        // Test seating areas
        let areas = try await store.listSeatingAreas()
        #expect(areas.count >= 3, "Should have at least 3 seating areas")
        
        // Test tables
        let tables = try await store.listTables()
        #expect(tables.count >= 13, "Should have at least 13 tables")
        
        // Verify table distribution across areas
        let areaIds = Set(areas.map { $0.id })
        let tableAreaIds = Set(tables.map { $0.areaId })
        #expect(tableAreaIds.isSubset(of: areaIds), "All tables should belong to valid areas")
        
        // Test that orders use the new menu items
        let orderMenuIds = Set(orders.flatMap { $0.items.map { $0.menuItemId } })
        let menuItemIds = Set(menuItems.map { $0.id })
        #expect(orderMenuIds.isSubset(of: menuItemIds), "Orders should only use valid menu items")
        
        // Test that recipes map to valid inventory SKUs
        let recipeSkus = Set(recipes.flatMap { $0.components.map { $0.sku } })
        let inventorySkus = Set(inventory.map { $0.sku })
        #expect(recipeSkus.isSubset(of: inventorySkus), "Recipes should only reference valid inventory SKUs")
        
        print("✅ Enhanced test data verification passed:")
        print("   - Inventory: \(inventory.count) items")
        print("   - Menu: \(menuItems.count) items")
        print("   - Recipes: \(recipes.count) recipes")
        print("   - Orders: \(orders.count) orders across \(uniqueDays.count) days")
        print("   - Reservations: \(reservations.count) reservations")
        print("   - Seating Areas: \(areas.count) areas")
        print("   - Tables: \(tables.count) tables")
    }
    
    @Test
    func testCSVExportDataGeneration() async throws {
        // Create a test store with enhanced data
        let store = TestableMongoStore(seedDummyData: true)
        
        // Simulate the CSV export logic
        var dayToIngredientQty: [String: [String: Double]] = [:]
        var dayToItemsTotal: [String: Double] = [:]
        var dayToOrdersTotal: [String: Int] = [:]
        
        let calendar = Calendar.current
        
        // Load recipes
        let recipes = try await store.listRecipes()
        var recipeMap: [String: [RecipeComponent]] = [:]
        for r in recipes {
            recipeMap[r.menuItemId] = r.components
        }
        
        // Process orders
        let orders = try await store.listOrders()
        for order in orders {
            let dayKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: order.createdAt))
            dayToOrdersTotal[dayKey, default: 0] += 1
            
            for item in order.items {
                dayToItemsTotal[dayKey, default: 0.0] += Double(item.quantity)
                
                if let components = recipeMap[item.menuItemId] {
                    for component in components {
                        let factor = component.unitsPerItem * (1.0 + (component.wastageRate ?? 0.0))
                        let used = Double(item.quantity) * factor
                        dayToIngredientQty[component.sku, default: [:]][dayKey, default: 0.0] += used
                    }
                }
            }
        }
        
        // Verify we have data for multiple SKUs
        #expect(dayToIngredientQty.count >= 8, "Should have usage data for at least 8 SKUs")
        
        // Verify we have data for multiple days
        let allDays = Set(dayToIngredientQty.values.flatMap { $0.keys })
        #expect(allDays.count >= 30, "Should have data for at least 30 days")
        
        // Verify each SKU has data for multiple days
        for (sku, dayData) in dayToIngredientQty {
            #expect(dayData.count >= 10, "SKU \(sku) should have data for at least 10 days")
        }
        
        // Verify we have meaningful usage values
        let totalUsage = dayToIngredientQty.values.flatMap { $0.values }.reduce(0, +)
        #expect(totalUsage > 0, "Total ingredient usage should be greater than 0")
        
        print("✅ CSV export data verification passed:")
        print("   - SKUs with data: \(dayToIngredientQty.count)")
        print("   - Days with data: \(allDays.count)")
        print("   - Total ingredient usage: \(totalUsage)")
        print("   - SKUs: \(dayToIngredientQty.keys.sorted())")
    }
    
    @Test
    func testActualCSVFileGeneration() async throws {
        // Create a test store with enhanced data
        let store = TestableMongoStore(seedDummyData: true)
        
        // Simulate the exact CSV export logic from CafePredictorController
        var dayToIngredientQty: [String: [String: Double]] = [:]
        var dayToItemsTotal: [String: Double] = [:]
        var dayToOrdersTotal: [String: Int] = [:]
        
        let calendar = Calendar.current
        
        // Load recipes
        let recipes = try await store.listRecipes()
        var recipeMap: [String: [RecipeComponent]] = [:]
        for r in recipes {
            recipeMap[r.menuItemId] = r.components
        }
        
        // Process orders
        let orders = try await store.listOrders()
        for order in orders {
            let dayKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: order.createdAt))
            dayToOrdersTotal[dayKey, default: 0] += 1
            
            for item in order.items {
                dayToItemsTotal[dayKey, default: 0.0] += Double(item.quantity)
                
                if let components = recipeMap[item.menuItemId] {
                    for component in components {
                        let factor = component.unitsPerItem * (1.0 + (component.wastageRate ?? 0.0))
                        let used = Double(item.quantity) * factor
                        dayToIngredientQty[component.sku, default: [:]][dayKey, default: 0.0] += used
                    }
                }
            }
        }
        
        // Generate CSV content exactly like the controller
        var csvContent = "sku,date,year,month,day,hour,isWeekend,ordersCount,itemsTotal,usageQty,usageQtyLog,usageQtySqrt,usageQtyCbrt,usageQtyFourth\n"
        
        // Collect all unique days
        var allDays: Set<String> = []
        for m in dayToIngredientQty.values {
            for k in m.keys {
                allDays.insert(k)
            }
        }
        let sortedDays = allDays.map { $0 }.sorted { $0 < $1 }
        
        // Generate rows for each SKU and day
        let allSkus = dayToIngredientQty.keys.sorted()
        for sku in allSkus {
            for dayKey in sortedDays {
                let date = ISO8601DateFormatter().date(from: dayKey) ?? Date()
                let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                let isWeekend = calendar.component(.weekday, from: date) == 1 || calendar.component(.weekday, from: date) == 7
                
                let ordersCount = dayToOrdersTotal[dayKey] ?? 0
                let itemsTotal = dayToItemsTotal[dayKey] ?? 0.0
                let usageQty = dayToIngredientQty[sku]?[dayKey] ?? 0.0
                
                let usageQtyLog = usageQty > 0 ? log(usageQty) : 0.0
                let usageQtySqrt = sqrt(usageQty)
                let usageQtyCbrt = pow(usageQty, 1.0/3.0)
                let usageQtyFourth = pow(usageQty, 0.25)
                
                csvContent += "\(sku),\(dayKey),\(comps.year ?? 0),\(comps.month ?? 0),\(comps.day ?? 0),\(comps.hour ?? 0),\(isWeekend),\(ordersCount),\(String(format: "%.4f", itemsTotal)),\(String(format: "%.4f", usageQty)),\(String(format: "%.4f", usageQtyLog)),\(String(format: "%.4f", usageQtySqrt)),\(String(format: "%.4f", usageQtyCbrt)),\(String(format: "%.4f", usageQtyFourth))\n"
            }
        }
        
        // Verify CSV content
        let lines = csvContent.components(separatedBy: "\n")
        #expect(lines.count > 1000, "CSV should have more than 1000 lines (header + data)")
        
        // Check header
        #expect(lines[0] == "sku,date,year,month,day,hour,isWeekend,ordersCount,itemsTotal,usageQty,usageQtyLog,usageQtySqrt,usageQtyCbrt,usageQtyFourth", "CSV header should match expected format")
        
        // Check data lines
        let dataLines = lines.dropFirst().filter { !$0.isEmpty }
        #expect(dataLines.count >= 4000, "Should have at least 4000 data rows (12 SKUs × 366 days)")
        
        // Verify we have data for all SKUs
        let skusInCSV = Set(dataLines.map { $0.components(separatedBy: ",")[0] })
        #expect(skusInCSV.count >= 12, "CSV should contain data for at least 12 SKUs")
        
        // Verify we have data for multiple days
        let daysInCSV = Set(dataLines.map { $0.components(separatedBy: ",")[1] })
        #expect(daysInCSV.count >= 300, "CSV should contain data for at least 300 days")
        
        // Check a sample data line format
        if let sampleLine = dataLines.first {
            let parts = sampleLine.components(separatedBy: ",")
            #expect(parts.count == 14, "Each CSV row should have 14 columns")
            #expect(Int(parts[2]) != nil, "Year should be numeric")
            #expect(Int(parts[3]) != nil, "Month should be numeric")
            #expect(Int(parts[4]) != nil, "Day should be numeric")
            #expect(Double(parts[8]) != nil, "Usage quantity should be numeric")
        }
        
        print("✅ CSV file generation verification passed:")
        print("   - Total lines: \(lines.count)")
        print("   - Data rows: \(dataLines.count)")
        print("   - SKUs in CSV: \(skusInCSV.count)")
        print("   - Days in CSV: \(daysInCSV.count)")
        print("   - Sample line: \(dataLines.first ?? "No data")")
    }
    
    @Test
    func testCSVFileForCreateML() async throws {
        // Create a test store with enhanced data
        let store = TestableMongoStore(seedDummyData: true)
        
        // Generate CSV content exactly like the controller
        var dayToIngredientQty: [String: [String: Double]] = [:]
        var dayToItemsTotal: [String: Double] = [:]
        var dayToOrdersTotal: [String: Int] = [:]
        
        let calendar = Calendar.current
        
        // Load recipes
        let recipes = try await store.listRecipes()
        var recipeMap: [String: [RecipeComponent]] = [:]
        for r in recipes {
            recipeMap[r.menuItemId] = r.components
        }
        
        // Process orders
        let orders = try await store.listOrders()
        for order in orders {
            let dayKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: order.createdAt))
            dayToOrdersTotal[dayKey, default: 0] += 1
            
            for item in order.items {
                dayToItemsTotal[dayKey, default: 0.0] += Double(item.quantity)
                
                if let components = recipeMap[item.menuItemId] {
                    for component in components {
                        let factor = component.unitsPerItem * (1.0 + (component.wastageRate ?? 0.0))
                        let used = Double(item.quantity) * factor
                        dayToIngredientQty[component.sku, default: [:]][dayKey, default: 0.0] += used
                    }
                }
            }
        }
        
        // Generate CSV content exactly like the controller
        var csvContent = "sku,date,year,month,day,hour,isWeekend,ordersCount,itemsTotal,usageQty,usageQtyLog,usageQtySqrt,usageQtyCbrt,usageQtyFourth\n"
        
        // Collect all unique days
        var allDays: Set<String> = []
        for m in dayToIngredientQty.values {
            for k in m.keys {
                allDays.insert(k)
            }
        }
        let sortedDays = allDays.map { $0 }.sorted { $0 < $1 }
        
        // Generate rows for each SKU and day
        let allSkus = dayToIngredientQty.keys.sorted()
        for sku in allSkus {
            for dayKey in sortedDays {
                let date = ISO8601DateFormatter().date(from: dayKey) ?? Date()
                let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                let isWeekend = calendar.component(.weekday, from: date) == 1 || calendar.component(.weekday, from: date) == 7
                
                let ordersCount = dayToOrdersTotal[dayKey] ?? 0
                let itemsTotal = dayToItemsTotal[dayKey] ?? 0.0
                let usageQty = dayToIngredientQty[sku]?[dayKey] ?? 0.0
                
                let usageQtyLog = usageQty > 0 ? log(usageQty) : 0.0
                let usageQtySqrt = sqrt(usageQty)
                let usageQtyCbrt = pow(usageQty, 1.0/3.0)
                let usageQtyFourth = pow(usageQty, 0.25)
                
                csvContent += "\(sku),\(dayKey),\(comps.year ?? 0),\(comps.month ?? 0),\(comps.day ?? 0),\(comps.hour ?? 0),\(isWeekend),\(ordersCount),\(String(format: "%.4f", itemsTotal)),\(String(format: "%.4f", usageQty)),\(String(format: "%.4f", usageQtyLog)),\(String(format: "%.4f", usageQtySqrt)),\(String(format: "%.4f", usageQtyCbrt)),\(String(format: "%.4f", usageQtyFourth))\n"
            }
        }
        
        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let csvFile = tempDir.appendingPathComponent("test_export.csv")
        try csvContent.write(to: csvFile, atomically: true, encoding: .utf8)
        
        // Test the CSV parsing logic similar to your CreateML code
        let raw = try String(contentsOf: csvFile, encoding: .utf8)
        let lines = raw.split(whereSeparator: \.isNewline).map { String($0) }
        
        #expect(lines.count > 1000, "CSV should have more than 1000 lines")
        
        // Test header parsing
        guard let headerLine = lines.first else {
            throw TestError("Missing header in CSV")
        }
        let headerCols = headerLine.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        #expect(headerCols.count >= 2, "Should have at least 2 columns")
        
        // Test data rows
        let dataLines = Array(lines.dropFirst())
        #expect(dataLines.count >= 4000, "Should have at least 4000 data rows")
        
        // Test target column (last column) is numeric
        let target = headerCols.last!
        #expect(target == "usageQtyFourth", "Target column should be usageQtyFourth")
        
        // Test that target values are numeric
        for line in dataLines.prefix(10) {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            if let last = parts.last {
                let isNumeric = Double(last) != nil
                #expect(isNumeric, "Target value '\(last)' should be numeric")
            }
        }
        
        // Test feature columns (excluding date, isWeekend)
        let featureColumns = Array(headerCols.dropLast()).filter { !["date", "datetime", "isWeekend"].contains($0) }
        #expect(featureColumns.count >= 5, "Should have at least 5 feature columns")
        
        print("✅ CreateML CSV compatibility test passed:")
        print("   - Total lines: \(lines.count)")
        print("   - Data rows: \(dataLines.count)")
        print("   - Header columns: \(headerCols.count)")
        print("   - Feature columns: \(featureColumns.count)")
        print("   - Target column: \(target)")
        print("   - Sample data: \(dataLines.first ?? "No data")")
        
        // Clean up
        try? FileManager.default.removeItem(at: csvFile)
    }
    
    @Test
    func testCreateMLParsingLogic() async throws {
        // Create a test store with enhanced data
        let store = TestableMongoStore(seedDummyData: true)
        
        // Generate CSV content exactly like the controller
        var dayToIngredientQty: [String: [String: Double]] = [:]
        var dayToItemsTotal: [String: Double] = [:]
        var dayToOrdersTotal: [String: Int] = [:]
        
        let calendar = Calendar.current
        
        // Load recipes
        let recipes = try await store.listRecipes()
        var recipeMap: [String: [RecipeComponent]] = [:]
        for r in recipes {
            recipeMap[r.menuItemId] = r.components
        }
        
        // Process orders
        let orders = try await store.listOrders()
        for order in orders {
            let dayKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: order.createdAt))
            dayToOrdersTotal[dayKey, default: 0] += 1
            
            for item in order.items {
                dayToItemsTotal[dayKey, default: 0.0] += Double(item.quantity)
                
                if let components = recipeMap[item.menuItemId] {
                    for component in components {
                        let factor = component.unitsPerItem * (1.0 + (component.wastageRate ?? 0.0))
                        let used = Double(item.quantity) * factor
                        dayToIngredientQty[component.sku, default: [:]][dayKey, default: 0.0] += used
                    }
                }
            }
        }
        
        // Generate CSV content exactly like the controller
        var csvContent = "sku,date,year,month,day,hour,isWeekend,ordersCount,itemsTotal,usageQty,usageQtyLog,usageQtySqrt,usageQtyCbrt,usageQtyFourth\n"
        
        // Collect all unique days
        var allDays: Set<String> = []
        for m in dayToIngredientQty.values {
            for k in m.keys {
                allDays.insert(k)
            }
        }
        let sortedDays = allDays.map { $0 }.sorted { $0 < $1 }
        
        // Generate rows for each SKU and day
        let allSkus = dayToIngredientQty.keys.sorted()
        for sku in allSkus {
            for dayKey in sortedDays {
                let date = ISO8601DateFormatter().date(from: dayKey) ?? Date()
                let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                let isWeekend = calendar.component(.weekday, from: date) == 1 || calendar.component(.weekday, from: date) == 7
                
                let ordersCount = dayToOrdersTotal[dayKey] ?? 0
                let itemsTotal = dayToItemsTotal[dayKey] ?? 0.0
                let usageQty = dayToIngredientQty[sku]?[dayKey] ?? 0.0
                
                let usageQtyLog = usageQty > 0 ? log(usageQty) : 0.0
                let usageQtySqrt = sqrt(usageQty)
                let usageQtyCbrt = pow(usageQty, 1.0/3.0)
                let usageQtyFourth = pow(usageQty, 0.25)
                
                csvContent += "\(sku),\(dayKey),\(comps.year ?? 0),\(comps.month ?? 0),\(comps.day ?? 0),\(comps.hour ?? 0),\(isWeekend),\(ordersCount),\(String(format: "%.4f", itemsTotal)),\(String(format: "%.4f", usageQty)),\(String(format: "%.4f", usageQtyLog)),\(String(format: "%.4f", usageQtySqrt)),\(String(format: "%.4f", usageQtyCbrt)),\(String(format: "%.4f", usageQtyFourth))\n"
            }
        }
        
        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let csvFile = tempDir.appendingPathComponent("debug_export.csv")
        try csvContent.write(to: csvFile, atomically: true, encoding: .utf8)
        
        // Test the EXACT parsing logic from your CreateML code
        print("🔍 Debug: Testing CreateML parsing logic...")
        
        let raw = try String(contentsOf: csvFile, encoding: .utf8)
        print("🔍 Debug: Raw content length: \(raw.count)")
        print("🔍 Debug: First 500 chars: \(String(raw.prefix(500)))")
        
        guard let headerLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) else {
            throw TestError("Missing header in CSV")
        }
        print("🔍 Debug: Header line: \(headerLine)")
        
        let headerCols = headerLine.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        print("🔍 Debug: Header columns (\(headerCols.count)): \(headerCols)")
        
        guard headerCols.count >= 2 else {
            throw TestError("Insufficient columns in CSV header")
        }
        
        let target = headerCols.last!
        print("🔍 Debug: Target column: \(target)")
        
        // Test csvTargetStats function
        let stats = try csvTargetStats(csvFile)
        print("🔍 Debug: CSV stats - rows: \(stats.rowCount), labels: \(stats.labels)")
        
        // Test csvTargetLooksNumeric function
        let isNumeric = try csvTargetLooksNumeric(csvFile)
        print("🔍 Debug: Target looks numeric: \(isNumeric)")
        
        #expect(stats.rowCount > 0, "Should have more than 0 rows")
        #expect(stats.rowCount >= 4000, "Should have at least 4000 rows")
        
        print("✅ CreateML parsing logic test passed:")
        print("   - Rows found: \(stats.rowCount)")
        print("   - Target column: \(target)")
        print("   - Is numeric: \(isNumeric)")
        print("   - Unique values: \(stats.labels.count)")
        
        // Clean up
        try? FileManager.default.removeItem(at: csvFile)
    }
    
    // Helper: detect whether target column (last column) appears numeric from CSV contents
    private func csvTargetLooksNumeric(_ url: URL) throws -> Bool {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var lines = raw.split(whereSeparator: \.isNewline).map { String($0) }
        guard lines.count >= 2 else { return false }
        lines.removeFirst() // drop header
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            guard let last = parts.last else { continue }
            return Double(last) != nil
        }
        return false
    }
    
    // Helper: compute total rows and label distribution for the last column
    private func csvTargetStats(_ url: URL) throws -> (rowCount: Int, labels: [String: Int]) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var lines = raw.split(whereSeparator: \.isNewline).map { String($0) }
        guard !lines.isEmpty else { return (0, [:]) }
        lines.removeFirst() // header
        var total = 0
        var counts: [String: Int] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            if let last = parts.last {
                counts[last, default: 0] += 1
                total += 1
            }
        }
        return (total, counts)
    }
    
}

struct TestError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

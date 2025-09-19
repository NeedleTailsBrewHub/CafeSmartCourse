//
//  CafePredictorController.swift
//  CafeSmartAPI
//
//  ML-Powered Cafe Management Controller
//  ====================================
//
//  This controller demonstrates how to integrate machine learning predictions
//  with real business logic in a Vapor API. It shows the complete workflow
//  from data preparation to ML predictions to business decisions.
//
//  Key Concepts Covered:
//  - ML model management (upload, activation, instantiation)
//  - Feature engineering from business data
//  - Time-series forecasting for inventory management
//  - Business logic integration with ML predictions
//  - CSV export for model training data
//  - Real-time notifications and background processing
//
//  Teaching Focus:
//  - End-to-end ML integration in APIs
//  - Feature engineering best practices
//  - Business logic with ML predictions
//  - Data preparation for ML models
//  - RESTful API design for ML services
//

import Foundation
import Vapor
import CoreML
@preconcurrency import BSON
import MongoKitten

// MARK: - CafePredictorController
// ==============================

/// Main controller for ML-powered cafe management operations
/// 
/// This controller integrates Core ML predictions with cafe business logic,
/// providing endpoints for:
/// - Model management (upload, activate, instantiate)
/// - Demand forecasting for inventory items
/// - Restock decision automation
/// - CSV export for model training data
/// - Background processing and notifications
///
/// Key Features:
/// - Real-time demand forecasting using Core ML models
/// - Automated restock decisions based on ML predictions
/// - Feature engineering from historical order data
/// - CSV export for model training and validation
/// - Background processing for continuous monitoring
struct CafePredictorController {
    
    // MARK: - Properties
    
    /// Collection names for database operations
    private let predictionsCollection = "forecasts"
    private let ordersCollection = "orders"
    
    // MARK: - CSV Export Functionality
    // ===============================
    
    /// Export CSV data for ML model training
    /// 
    /// This endpoint generates CSV files containing historical data
    /// that can be used to train or validate ML models. It processes
    /// orders, recipes, and inventory data to create feature-rich
    /// datasets for time-series forecasting.
    ///
    /// The CSV includes features like:
    /// - Historical usage patterns (lag features)
    /// - Temporal features (day, month, weekday, etc.)
    /// - Order volume metrics
    /// - Rolling averages and trends
    ///
    /// - Parameter req: The HTTP request
    /// - Returns: CSV file response
    /// - Throws: Errors for data processing or file operations
    func exportCSV(req: Request) async throws -> Response {
        // Get query parameters
        let qMode = (try? req.query.get(String.self, at: "mode")) ?? "ingredientDaily"
//        let qSku = try? req.query.get(String.self, at: "sku")
        
        // Validate export mode
        guard qMode == "ingredientDaily" else {
            throw Abort(.badRequest, reason: "Only 'ingredientDaily' mode is supported")
        }
        
        // Initialize data structures for aggregation
        var dayToIngredientQty: [String: [DayBucket: Double]] = [:]
        var dayToItemsTotal: [DayBucket: Double] = [:]
        var dayToOrdersTotal: [DayBucket: Int] = [:]
        
        // Setup calendar and date formatter
        let calendar = Calendar.current
        let df = ISO8601DateFormatter()
        
        // Prepare temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("export_\(UUID().uuidString).csv")
        
        // Helper function to write to file
        func write(_ content: String) throws {
            if FileManager.default.fileExists(atPath: tempFile.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: tempFile)
                defer { try? fileHandle.close() }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: content.data(using: .utf8)!)
            } else {
                // Create new file
                try content.write(to: tempFile, atomically: true, encoding: .utf8)
            }
        }
        
        // Helper function to get start of day
        func startOfDay(_ date: Date) -> Date {
            calendar.startOfDay(for: date)
        }
        
        // Load recipes to map menu items to ingredients
        var recipeMap: [String: [RecipeComponent]] = [:]
        let recipes = try await req.store.listRecipes()
        for r in recipes {
            recipeMap[r.menuItemId] = r.components
        }
        
        // Process orders from test store
        func makeEvent(type: String, ts: Date) -> CafeEventDB {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: ts)
            return CafeEventDB(
                type: type,
                ts: ts,
                year: comps.year ?? 0,
                month: comps.month ?? 0,
                day: comps.day ?? 0,
                hour: comps.hour ?? 0,
                weekday: comps.weekday ?? 0,
                orderId: nil,
                channel: nil,
                serviceType: nil,
                secondsToComplete: nil,
                menuItemId: nil,
                quantity: nil,
                inventoryItemId: nil,
                sku: nil,
                level: nil,
                threshold: nil,
                reservationId: nil,
                partySize: nil,
                areaId: nil,
                tableId: nil,
                priceCents: nil,
                available: nil
            )
        }
        
        var events: [CafeEventDB] = []
        
        // Convert orders to events
        let orders = try await req.store.listOrders()
        for o in orders {
            var created = makeEvent(type: "orderCreated", ts: o.createdAt)
            created.orderId = o.id
            created.channel = o.channel?.rawValue
            created.serviceType = o.serviceType?.rawValue
            events.append(created)
            
            for it in o.items {
                var dem = makeEvent(type: "orderItemDemand", ts: o.createdAt)
                dem.orderId = o.id
                dem.menuItemId = it.menuItemId
                dem.quantity = Double(it.quantity)
                dem.channel = o.channel?.rawValue
                dem.serviceType = o.serviceType?.rawValue
                events.append(dem)
            }
            
            if o.status == .completed {
                var comp = makeEvent(type: "orderCompleted", ts: o.createdAt.addingTimeInterval(120))
                comp.orderId = o.id
                comp.channel = o.channel?.rawValue
                comp.serviceType = o.serviceType?.rawValue
                comp.secondsToComplete = max(10.0, Date().timeIntervalSince(o.createdAt))
                events.append(comp)
            }
        }
        
        // Convert reservations to events
        let reservations = try await req.store.listReservations()
        for r in reservations {
            var ev = makeEvent(type: "reservationCreated", ts: r.startTime)
            ev.reservationId = r.id
            ev.partySize = r.partySize
            ev.areaId = r.areaId
            ev.tableId = r.tableId
            events.append(ev)
        }
        
        // Process events for ingredient daily aggregation
        for ev in events {
            if ev.type == "orderItemDemand", let q = ev.quantity, let mid = ev.menuItemId {
                let db = DayBucket(date: startOfDay(ev.ts))
                dayToItemsTotal[db, default: 0.0] += q
                
                if let comps = recipeMap[mid] {
                    for c in comps {
                        let factor = c.unitsPerItem * (1.0 + (c.wastageRate ?? 0.0))
                        let used = q * factor
                        var m = dayToIngredientQty[c.sku] ?? [:]
                        m[db, default: 0.0] += used
                        dayToIngredientQty[c.sku] = m
                    }
                }
            }
            
            if ev.type == "orderCreated" {
                let db = DayBucket(date: startOfDay(ev.ts))
                dayToOrdersTotal[db, default: 0] += 1
            }
        }
        
        // MARK: - CSV Generation
        
        let skuParam: String? = try? req.query.get(String.self, at: "sku")
        var allDays: Set<DayBucket> = []
        for m in dayToIngredientQty.values {
            for k in m.keys {
                allDays.insert(k)
            }
        }
        let sortedDays = allDays.map { $0 }.sorted { $0.date < $1.date }
        
        func usage(_ sku: String, _ d: DayBucket) -> Double {
            return dayToIngredientQty[sku]?[d] ?? 0.0
        }
        
        func orderCount(_ d: DayBucket) -> Int {
            return dayToOrdersTotal[d] ?? 0
        }
        
        func items(_ d: DayBucket) -> Double {
            return dayToItemsTotal[d] ?? 0.0
        }
        
        func writeGenericHeader() throws {
            let header = [
                "sku", "date", "year", "month", "day", "weekday", "is_weekend",
                "orders_total_lag_1d", "items_total_lag_1d",
                "usage_lag_1d", "usage_lag_7d", "rolling_usage_last_7d",
                "usage_same_weekday_lag_28d",
                "target_usage",
            ].joined(separator: ",") + "\n"
            try write(header)
        }
        
        func emitRows(for sku: String) throws {
            for db in sortedDays {
                let d = db.date
                let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
                let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
                let dLag1 = DayBucket(date: calendar.date(byAdding: .day, value: -1, to: d)!)
                let dLag7 = DayBucket(date: calendar.date(byAdding: .day, value: -7, to: d)!)
                let dLag28 = DayBucket(date: calendar.date(byAdding: .day, value: -28, to: d)!)
                
                var sum: Double = 0
                var cnt: Int = 0
                for k in 1...7 {
                    sum += usage(sku, DayBucket(date: calendar.date(byAdding: .day, value: -k, to: d)!))
                    cnt += 1
                }
                let avg7 = cnt > 0 ? sum / Double(cnt) : 0.0
                
                let row: [String] = [
                    sku,
                    df.string(from: d),
                    String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                    String(comps.weekday ?? 0), isWeekend ? "true" : "false",
                    String(orderCount(dLag1)), String(format: "%.4f", items(dLag1)),
                    String(format: "%.4f", usage(sku, dLag1)), String(format: "%.4f", usage(sku, dLag7)),
                    String(format: "%.4f", avg7), String(format: "%.4f", usage(sku, dLag28)),
                    String(format: "%.4f", usage(sku, db)),
                ]
                try write(row.joined(separator: ",") + "\n")
            }
        }
        
        if let sku = skuParam, !sku.isEmpty {
            try writeGenericHeader()
            try emitRows(for: sku)
        } else {
            try writeGenericHeader()
            let allSkus = dayToIngredientQty.keys.sorted()
            for sku in allSkus {
                try emitRows(for: sku)
            }
        }
        
        // Create response with CSV data
        let data = try Data(contentsOf: tempFile)
        let buffer = ByteBufferAllocator().buffer(data: data)
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempFile)
        
        return Response(
            status: .ok,
            headers: HTTPHeaders([
                ("Content-Type", "text/csv"),
                ("Content-Disposition", "attachment; filename=\"cafe_data_\(Date().timeIntervalSince1970).csv\"")
            ]),
            body: Response.Body(buffer: buffer)
        )
    }
    
    // MARK: - Model Management
    // =======================
    
    /// Upload a new ML model
    /// 
    /// This endpoint handles model file uploads, storing them in the
    /// appropriate directory structure and registering them in the database.
    /// It also automatically activates the model and triggers background
    /// processing for restock decisions.
    ///
    /// - Parameter req: The HTTP request containing the model file
    /// - Returns: Model upload response with metadata
    /// - Throws: Errors for file operations or model validation
    func uploadModel(req: Request) async throws -> ModelUploadResponse {
        // Extract query parameters
        let qName = (try? req.query.get(String.self, at: "name")) ?? ""
        let qRuntime = (try? req.query.get(String.self, at: "runtime")) ?? "coreml"
        let qKind = (try? req.query.get(String.self, at: "kind")) ?? "restockDaily"
        
        // Validate request body
        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "Empty request body")
        }
        
        // Process filename and ensure proper extension
        let providedName = (qName.isEmpty == false ? qName : nil) ?? "model.mlmodel"
        
        // Ensure the filename has .mlmodel extension
        var filename = providedName
        if !filename.hasSuffix(".mlmodel") {
            filename += ".mlmodel"
        }
        filename = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: ".")
        
        let kind = PredictorKind(rawValue: qKind) ?? .restockDaily
        let modelsRoot = req.application.directory.workingDirectory + "Models/" + qRuntime + "/" + kind.rawValue + "/"
        try FileManager.default.createDirectory(atPath: modelsRoot, withIntermediateDirectories: true)
        let targetPath = modelsRoot + filename
        try await req.fileio.writeFile(buffer, at: targetPath)
        
        // Get file attributes
        let attrs = try FileManager.default.attributesOfItem(atPath: targetPath)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? buffer.readableBytes
        
        // Create model artifact record
        let _id = ObjectId()
        let artifact = MLModelArtifact(
            _id: _id,
            id: _id.hexString,
            filename: filename,
            runtime: PredictRuntime(rawValue: qRuntime)!,
            kind: kind,
            storedAt: targetPath,
            bytes: size,
            active: false,
            uploadedAt: Date()
        )
        try await req.application.mongoStore.createModelArtifact(artifact)
        await req.application.realtime.publish(.modelUploaded(artifact), to: .merchant)
        
        // Activate and instantiate the model
        try await activateModel(req: req, id: artifact._id)
        try await instantiateModel(req: req, kind: kind)
        
        // Trigger background sweep for restock decisions
        let results = await self.computeRestockDecisions(app: req.application)
        for result in results where result.decision.needRestock {
            await req.application.realtime.publish(.inventory(.runningLow(result.item)), to: .merchant)
        }
        
        return ModelUploadResponse(
            id: artifact._id.hexString,
            filename: filename,
            runtime: qRuntime,
            bytes: size,
            storedAt: targetPath,
            kind: kind.rawValue,
            active: artifact.active
        )
    }
    
    /// List all available models
    /// 
    /// Returns a list of all ML models stored in the system,
    /// including their metadata and activation status.
    ///
    /// - Parameter req: The HTTP request
    /// - Returns: List of model artifacts
    /// - Throws: Errors for database operations
    func listModels(req: Request) async throws -> MLModelsWrapper {
        let result = try await req.application.mongoStore.listModelArtifacts()
        return MLModelsWrapper(items: result)
    }
    
    /// Activate a specific model
    /// 
    /// Activates a model by its ID, making it the active model
    /// for its kind (e.g., restockDaily).
    ///
    /// - Parameter req: The HTTP request containing model ID
    /// - Returns: Success status
    /// - Throws: Errors for database operations or model activation
    func activateModel(req: Request) async throws -> HTTPStatus {
        struct Activate: Content {
            var id: String
        }
        let body = try req.content.decode(Activate.self)
        guard let oid = ObjectId(body.id) else { throw Abort(.badRequest) }
        try await activateModel(req: req, id: oid)
        return .ok
    }
    
    /// Internal method to activate a model by ObjectId
    private func activateModel(req: Request, id: ObjectId) async throws {
        try await req.application.mongoStore.setActiveModel(id: id.hexString)
        await req.application.realtime.publish(.modelActivated(kind: .restockDaily, id: id.hexString), to: .merchant)
    }
    
    /// Instantiate a predictor for a specific kind
    /// 
    /// Loads and initializes a predictor for the specified kind,
    /// making it available for predictions.
    ///
    /// - Parameter req: The HTTP request containing predictor kind
    /// - Returns: Success status
    /// - Throws: Errors for model loading or instantiation
    func instantiatePredictor(req: Request) async throws -> HTTPStatus {
        struct Body: Content {
            var kind: String
        }
        let body = try req.content.decode(Body.self)
        let normalized = body.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = PredictorKind.allCases.first(where: { $0.rawValue.lowercased() == normalized.lowercased() }) else {
            throw Abort(.badRequest)
        }
        try await instantiateModel(req: req, kind: kind)
        return .ok
    }
    
    /// Internal method to instantiate a model
    private func instantiateModel(req: Request, kind: PredictorKind) async throws {
        let artifacts = try await req.application.mongoStore.listModelArtifacts()
        guard let artifact = artifacts.first(where: { $0.kind == kind && $0.active }) else {
            throw Abort(.notFound, reason: "No active model for kind \(kind.rawValue)")
        }
        let predictor = try await Predictor(modelPath: artifact.storedAt)
        await req.application.predictors.set(
            kind: kind, runtime: artifact.runtime, path: artifact.storedAt, predictor: predictor)
        await req.application.realtime.publish(.predictorReady(kind: kind), to: .merchant)
    }
    
    // MARK: - Core ML Prediction Methods
    // ==================================
    
    /// Get a predictor instance for the application
    /// 
    /// Retrieves a predictor from the registry, throwing an error
    /// if it's not available.
    ///
    /// - Parameters:
    ///   - app: The application instance
    ///   - kind: The predictor kind to retrieve
    /// - Returns: The predictor instance
    /// - Throws: Error if predictor is not ready
    private func requirePredictor(app: Application, _ kind: PredictorKind) async throws -> Predictor {
        guard let predictor = await app.predictors.get(kind) else {
            throw Abort(.failedDependency, reason: "Predictor not ready for \(kind.rawValue)")
        }
        return predictor
    }
    
    /// Check if running in testing mode
    /// 
    /// Determines if the application is running in testing mode
    /// based on environment variables and application state.
    ///
    /// - Parameter app: The application instance
    /// - Returns: True if in testing mode
    private func isTesting(app: Application) -> Bool {
        let useTestStoreEnv = (Environment.get("USE_TEST_STORE") ?? "").lowercased()
        return app.environment == .testing || useTestStoreEnv == "true"
    }
    
    /// Get inventory items from the appropriate store
    /// 
    /// Retrieves inventory items from either the test store or
    /// the production MongoDB database.
    ///
    /// - Parameter app: The application instance
    /// - Returns: Array of inventory items
    /// - Throws: Errors for database operations
    private func listInventoryItems(app: Application) async throws -> [InventoryItem] {
        if isTesting(app: app) {
            return try await app.mongoStore.listInventory()
        }
        var items: [InventoryItem] = []
        for try await doc in app.mongoDB["inventory_items"].find() {
            if let item = try? BSONDecoder().decode(InventoryItem.self, from: doc) {
                items.append(item)
            }
        }
        return items
    }
    
    // MARK: - ML Forecast Series
    // ==========================
    
    /// Generate demand forecast series for an inventory item
    /// 
    /// This method uses Core ML to predict future demand for a specific SKU.
    /// It calculates features from historical order data and uses the ML model
    /// to generate predictions for the specified horizon.
    ///
    /// Feature Engineering:
    /// - usage_lag_1d: Usage from 1 day ago
    /// - usage_lag_7d: Usage from 7 days ago
    /// - rolling_usage_last_7d: 7-day rolling average
    /// - usage_same_weekday_lag_28d: Usage from same weekday 4 weeks ago
    /// - Temporal features: day, month, year, weekday
    /// - Order metrics: orders_total_lag_1d, items_total_lag_1d
    ///
    /// - Parameters:
    ///   - app: The application instance
    ///   - horizon: Number of days to forecast
    ///   - sku: The SKU to forecast for
    /// - Returns: Array of predicted demand values
    /// - Throws: Errors for model prediction or data processing
    func forecastSeries(app: Application, horizon: Int, sku: String) async throws -> [Double] {
        let predictor = try await requirePredictor(app: app, .restockDaily)
        let (_, outName) = try await predictor.ioNames()
        
        // Get inventory item data
        let all = try await listInventoryItems(app: app)
        guard all.first(where: { $0.sku == sku }) != nil else {
            throw Abort(.notFound, reason: "Inventory item not found for sku \(sku)")
        }
        
        // Get historical order data
        let orders = try await app.mongoStore.listOrders()
        
        var ys: [Double] = []
        for dayOffset in 0..<horizon {
            let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            
            // Calculate real usage data from orders
            let usageLag1d = await calculateUsageFromOrders(orders: orders, sku: sku, daysAgo: 1, app: app)
            let usageLag7d = await calculateUsageFromOrders(orders: orders, sku: sku, daysAgo: 7, app: app)
            let rollingUsage7d = await calculateRollingUsage(orders: orders, sku: sku, days: 7, app: app)
            let usageSameWeekday28d = await calculateUsageFromOrders(orders: orders, sku: sku, daysAgo: 28, app: app)
            
            // Get order counts
            let ordersLag1d = calculateOrderCount(orders: orders, daysAgo: 1)
            let itemsLag1d = calculateItemsSold(orders: orders, daysAgo: 1)
            
            // Prepare input features for ML model
            let inputs: [String: Any] = [
                "usage_lag_1d": usageLag1d,
                "sku": sku,
                "day": Calendar.current.component(.day, from: targetDate),
                "weekday": Calendar.current.component(.weekday, from: targetDate),
                "month": Calendar.current.component(.month, from: targetDate),
                "orders_total_lag_1d": ordersLag1d,
                "year": Calendar.current.component(.year, from: targetDate),
                "usage_lag_7d": usageLag7d,
                "items_total_lag_1d": itemsLag1d,
                "rolling_usage_last_7d": rollingUsage7d,
                "usage_same_weekday_lag_28d": usageSameWeekday28d
            ]
            
            // Make prediction using Core ML model
            let out = try await predictor.predictMultiple(inputs: inputs, outputName: outName)
            ys.append(Double(out.first ?? 0))
        }
        return ys
    }
    
    // MARK: - Helper Methods for Data Calculation
    // ===========================================
    
    /// Calculate usage for a specific SKU from historical orders
    /// 
    /// This method processes order data to calculate how much of a specific
    /// ingredient (SKU) was used on a given day in the past. It uses recipe
    /// information to convert menu item orders into ingredient usage.
    ///
    /// - Parameters:
    ///   - orders: Array of historical orders
    ///   - sku: The SKU to calculate usage for
    ///   - daysAgo: Number of days in the past to calculate for
    ///   - app: The application instance for accessing store
    /// - Returns: Total usage amount for the specified day
    internal func calculateUsageFromOrders(orders: [Order], sku: String, daysAgo: Int, app: Application) async -> Double {
        let targetDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: targetDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        var totalUsage: Double = 0
        
        for order in orders {
            guard order.createdAt >= startOfDay && order.createdAt < endOfDay else { continue }
            
            for item in order.items {
                // Get recipe components for this menu item
                if let recipes = try? await app.mongoStore.findRecipes(menuItemId: item.menuItemId),
                   let recipe = recipes.first,
                   let component = recipe.components.first(where: { $0.sku == sku }) {
                    let usage = Double(item.quantity) * component.unitsPerItem * (1.0 + (component.wastageRate ?? 0.0))
                    totalUsage += usage
                }
            }
        }
        
        return totalUsage
    }
    
    /// Calculate rolling average usage over a specified number of days
    /// 
    /// This method calculates the average daily usage over a rolling window
    /// of the specified number of days. It's useful for smoothing out
    /// daily variations and identifying trends.
    ///
    /// - Parameters:
    ///   - orders: Array of historical orders
    ///   - sku: The SKU to calculate usage for
    ///   - days: Number of days in the rolling window
    ///   - app: The application instance for accessing store
    /// - Returns: Average daily usage over the rolling window
    internal func calculateRollingUsage(orders: [Order], sku: String, days: Int, app: Application) async -> Double {
        var totalUsage: Double = 0
        var validDays = 0
        
        for dayOffset in 1...days {
            let usage = await calculateUsageFromOrders(orders: orders, sku: sku, daysAgo: dayOffset, app: app)
            totalUsage += usage
            validDays += 1
        }
        
        return validDays > 0 ? totalUsage / Double(validDays) : 0.0
    }
    
    /// Calculate total number of orders from a specific day
    /// 
    /// This method counts the total number of orders placed on a given day
    /// in the past. It's used as a feature to understand order volume patterns.
    ///
    /// - Parameters:
    ///   - orders: Array of historical orders
    ///   - daysAgo: Number of days in the past to calculate for
    /// - Returns: Total number of orders for the specified day
    internal func calculateOrderCount(orders: [Order], daysAgo: Int) -> Int {
        let targetDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: targetDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        return orders.filter { order in
            order.createdAt >= startOfDay && order.createdAt < endOfDay
        }.count
    }
    
    /// Calculate total items sold on a specific day
    /// 
    /// This method calculates the total quantity of all items sold on a given day.
    /// It's used as a feature to understand overall sales volume.
    ///
    /// - Parameters:
    ///   - orders: Array of historical orders
    ///   - daysAgo: Number of days in the past to calculate for
    /// - Returns: Total quantity of items sold for the specified day
    internal func calculateItemsSold(orders: [Order], daysAgo: Int) -> Double {
        let targetDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: targetDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        var totalItems: Double = 0
        
        for order in orders {
            guard order.createdAt >= startOfDay && order.createdAt < endOfDay else { continue }
            
            for item in order.items {
                totalItems += Double(item.quantity)
            }
        }
        
        return totalItems
    }
    
    /// Calculate usage for a specific SKU from order data
    /// 
    /// This method calculates the total usage of a specific SKU from order data,
    /// taking into account recipe components and wastage rates.
    ///
    /// - Parameters:
    ///   - orders: Array of orders to process
    ///   - sku: The SKU to calculate usage for
    ///   - app: The application instance for accessing store
    /// - Returns: Total usage amount
    internal func calculateOrderUsage(orders: [Order], sku: String, app: Application) async -> Double {
        var totalUsage: Double = 0
        
        for order in orders {
            for item in order.items {
                if let recipes = try? await app.mongoStore.findRecipes(menuItemId: item.menuItemId),
                   let recipe = recipes.first,
                   let component = recipe.components.first(where: { $0.sku == sku }) {
                    let usage = Double(item.quantity) * component.unitsPerItem * (1.0 + (component.wastageRate ?? 0.0))
                    totalUsage += usage
                }
            }
        }
        
        return totalUsage
    }
    
    // MARK: - API Endpoints
    // =====================
    
    /// Request structure for restock decisions
    struct RestockDecisionRequest: Content {
        var sku: String
        var daysAhead: Int?
    }
    
    /// Response structure for restock decisions
    struct RestockDecisionResponse: Content {
        var sku: String
        var needRestock: Bool
        var reorderQty: Int
        var reorderPoint: Int
        var leadTimeDays: Int
        var onHand: Int
        var forecastSumNextLeadTime: Int
    }
    
    /// Make a restock decision for an inventory item
    /// 
    /// This endpoint combines ML predictions with business logic to determine
    /// if an inventory item needs to be restocked. It uses the forecast series
    /// to predict future demand and compares it with current inventory levels.
    ///
    /// Business Logic:
    /// - Reorder Point (ROP) = Safety Stock + Forecasted Demand During Lead Time
    /// - Need Restock = Current Stock ≤ Reorder Point
    /// - Reorder Quantity = max(Par Level - Current Stock, Minimum Reorder, 0)
    ///
    /// - Parameter req: The HTTP request containing SKU and optional days ahead
    /// - Returns: Restock decision with quantities and reasoning
    /// - Throws: Errors for data retrieval or ML prediction
    func decideRestock(req: Request) async throws -> RestockDecisionResponse {
        let body = try req.content.decode(RestockDecisionRequest.self)
        let res = try await decideRestock(app: req.application, sku: body.sku, daysAhead: body.daysAhead)
        return res
    }
    
    /// Internal method to make restock decisions
    /// 
    /// This method implements the core business logic for restock decisions.
    /// It retrieves inventory data, generates forecasts, and applies
    /// business rules to determine restock needs.
    ///
    /// - Parameters:
    ///   - app: The application instance
    ///   - sku: The SKU to make a decision for
    ///   - daysAhead: Optional number of days to forecast ahead
    /// - Returns: Restock decision response
    /// - Throws: Errors for data retrieval or ML prediction
    private func decideRestock(app: Application, sku: String, daysAhead: Int?) async throws -> RestockDecisionResponse {
        // Get inventory item data
        let all = try await listInventoryItems(app: app)
        guard let item = all.first(where: { $0.sku == sku }) else {
            throw Abort(.notFound, reason: "Inventory item not found for sku \(sku)")
        }

        // Inventory parameters (with defaults/validation)
        let currentOnHand = item.quantity                                  // current stock
        let leadTimeDays = max(1, item.leadTimeDays ?? 3)                  // min 1 day
        let safetyStockLevel = max(0, item.safetyStock ?? item.reorderThreshold) // non-negative
        let parLevel = item.parLevel                                       // optional target stock level
        let minimumReorderQty = max(0, item.reorderQuantity ?? 0)          // non-negative minimum order

        // Determine forecast horizon (use requested days or lead time; cap at 14)
        var forecastHorizon = max(1, daysAhead ?? leadTimeDays)
        forecastHorizon = min(forecastHorizon, 14)

        // Generate demand forecast series for the horizon
        let series = try await forecastSeries(app: app, horizon: forecastHorizon, sku: sku)

        // Demand expected during lead time (sum of first `leadTimeDays` entries; ignore negatives)
        let demandDuringLead = Int(series
            .prefix(leadTimeDays)
            .map { max(0.0, $0) }
            .reduce(0.0, +)
            .rounded())

        // Reorder point (ROP) and whether restock is needed
        let reorderPoint = safetyStockLevel + demandDuringLead
        let needsRestock = currentOnHand <= reorderPoint

        // Reorder quantity:
        // - If parLevel exists: order up to parLevel
        // - Otherwise: order up to reorderPoint
        // Always respect minimumReorderQty and never return negative
        let targetLevel = parLevel ?? reorderPoint
        let reorderQty = max(targetLevel - currentOnHand, minimumReorderQty, 0)

        return RestockDecisionResponse(
            sku: sku,
            needRestock: needsRestock,
            reorderQty: reorderQty,
            reorderPoint: reorderPoint,
            leadTimeDays: leadTimeDays,
            onHand: currentOnHand,
            forecastSumNextLeadTime: demandDuringLead
        )
    }

    
    // MARK: - Background Processing
    // ============================
    
    /// Structure for restock decision results with inventory item
    struct RestockDecisionWithItem {
        let item: InventoryItem
        let decision: RestockDecisionResponse
    }
    
    /// Compute restock decisions for all inventory items
    /// 
    /// This method processes all inventory items and generates restock
    /// decisions for each one. It's used for background processing
    /// and bulk operations.
    ///
    /// - Parameters:
    ///   - app: The application instance
    ///   - daysAhead: Optional number of days to forecast ahead
    /// - Returns: Array of restock decisions with inventory items
    func computeRestockDecisions(app: Application, daysAhead: Int? = nil) async -> [RestockDecisionWithItem] {
        var results: [RestockDecisionWithItem] = []
        
        do {
            let items = try await listInventoryItems(app: app)
            
            for item in items {
                do {
                    let decision = try await decideRestock(app: app, sku: item.sku, daysAhead: daysAhead)
                    results.append(RestockDecisionWithItem(item: item, decision: decision))
                } catch {
                    // Log error but continue processing other items
                    print("Error processing restock decision for \(item.sku): \(error)")
                }
            }
        } catch {
            print("Error retrieving inventory items: \(error)")
        }
        
        return results
    }
}

// MARK: - Supporting Types
// =======================

/// Response structure for model upload operations
struct ModelUploadResponse: Content {
    let id: String
    let filename: String
    let runtime: String
    let bytes: Int
    let storedAt: String
    let kind: String
    let active: Bool
}

/// Day bucket for time-series aggregation
struct DayBucket: Hashable {
    let date: Date
    
    init(date: Date) {
        self.date = date
    }
}

/// Database event structure for analytics
struct CafeEventDB {
    var type: String
    var ts: Date
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var weekday: Int
    var orderId: String?
    var channel: String?
    var serviceType: String?
    var secondsToComplete: Double?
    var menuItemId: String?
    var quantity: Double?
    var inventoryItemId: String?
    var sku: String?
    var level: Double?
    var threshold: Double?
    var reservationId: String?
    var partySize: Int?
    var areaId: String?
    var tableId: String?
    var priceCents: Int?
    var available: Bool?
}


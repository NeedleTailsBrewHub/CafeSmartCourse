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
        // Clients send `dataset=`; older callers used `mode=`.
        let qMode = (try? req.query.get(String.self, at: "dataset"))
            ?? (try? req.query.get(String.self, at: "mode"))
            ?? "ingredientDaily"
        let skuParam: String? = try? req.query.get(String.self, at: "sku")
        let csv: String
        switch qMode.lowercased() {
        case "ingredientdaily":
            csv = try await IngredientDailyCSV.forTraining(store: req.store, sku: skuParam)
        case "ordershourly", "workloadhourly":
            csv = try await OrdersHourlyCSV.forTraining(store: req.store)
        case "reservationshourly":
            csv = try await ReservationsHourlyCSV.forTraining(store: req.store)
        default:
            throw Abort(
                .badRequest,
                reason: "Unsupported dataset '\(qMode)'. Use ingredientDaily, ordersHourly, or reservationsHourly"
            )
        }
        var buffer = ByteBufferAllocator().buffer(capacity: csv.utf8.count)
        buffer.writeString(csv)
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
        let qName = (try? req.query.get(String.self, at: "name")) ?? ""
        let qRuntime = try? req.query.get(String.self, at: "runtime")
        let qKind = (try? req.query.get(String.self, at: "kind")) ?? "restockDaily"

        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "Empty request body")
        }

        let runtime: PredictRuntime
        do {
            runtime = try ModelUploadSupport.parseRuntime(qRuntime)
        } catch let error as PredictorError {
            switch error {
            case .unavailable:
                throw Abort(.serviceUnavailable, reason: error.description)
            default:
                throw Abort(.badRequest, reason: error.description)
            }
        }

        let filename = try ModelUploadSupport.sanitizedFilename(qName, runtime: runtime)
        let kind = PredictorKind(rawValue: qKind) ?? .restockDaily
        let modelsRoot = ModelUploadSupport.modelsRoot(
            workingDirectory: req.application.directory.workingDirectory,
            runtime: runtime,
            kind: kind
        )
        try FileManager.default.createDirectory(atPath: modelsRoot, withIntermediateDirectories: true)
        let targetPath = modelsRoot + filename
        try await req.fileio.writeFile(buffer, at: targetPath)

        let attrs = try FileManager.default.attributesOfItem(atPath: targetPath)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? buffer.readableBytes

        let id = ObjectId().hexString
        let artifact = MLModelArtifact(
            _id: id,
            id: id,
            filename: filename,
            runtime: runtime,
            kind: kind,
            storedAt: targetPath,
            bytes: size,
            active: false,
            uploadedAt: Date()
        )
        try await req.application.mongoStore.createModelArtifact(artifact)
        await req.application.realtime.publish(.modelUploaded(artifact), to: .merchant)

        try await activateModel(req: req, id: artifact._id)
        await ModelArtifactLifecycle.prune(app: req.application, kind: kind, runtime: runtime)

        if kind == .restockDaily {
            await publishRestockDecisions(app: req.application)
        }

        return ModelUploadResponse(
            id: artifact._id,
            filename: filename,
            runtime: runtime.rawValue,
            bytes: size,
            storedAt: targetPath,
            kind: kind.rawValue,
            active: true
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
    func listModels(req: Request) async throws -> ModelsList {
        let result = try await req.application.mongoStore.listModelArtifacts()
        return ModelsList(items: result)
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
        guard !body.id.isEmpty else { throw Abort(.badRequest) }
        try await activateModel(req: req, id: body.id)
        return .ok
    }

    /// Delete an inactive model artifact (active models must be replaced first).
    func deleteModel(req: Request) async throws -> HTTPStatus {
        struct DeleteBody: Content {
            var id: String
        }
        let body = try req.content.decode(DeleteBody.self)
        guard !body.id.isEmpty else { throw Abort(.badRequest) }
        try await ModelArtifactLifecycle.deleteInactive(app: req.application, id: body.id)
        return .ok
    }
    
    /// Activate by id, then load the predictor into the registry.
    private func activateModel(req: Request, id: String) async throws {
        guard try await req.application.mongoStore.findModelArtifact(by: id) != nil else {
            throw Abort(.notFound, reason: "Model artifact not found")
        }
        try await req.application.mongoStore.setActiveModel(id: id)
        let artifact = try await req.application.mongoStore.findModelArtifact(by: id)!
        await req.application.realtime.publish(.modelActivated(kind: artifact.kind, id: id), to: .merchant)
        try await instantiateModel(req: req, kind: artifact.kind)
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
        let predictor: any PredictorServing
        do {
            predictor = try await PredictorFactory.make(
                runtime: artifact.runtime, path: artifact.storedAt, kind: kind)
        } catch let error as PredictorError {
            throw Abort(.failedDependency, reason: error.description)
        }
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
    private func requirePredictor(app: Application, _ kind: PredictorKind) async throws -> any PredictorServing {
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
        // Get inventory item data
        let all = try await listInventoryItems(app: app)
        guard all.first(where: { $0.sku == sku }) != nil else {
            throw Abort(.notFound, reason: "Inventory item not found for sku \(sku)")
        }

        // Deterministic synthetic ramp in tests (no CoreML/ONNX dependency).
        if isTesting(app: app) {
            return (1...max(horizon, 0)).map { Double($0) }
        }

        let predictor = try await requirePredictor(app: app, .restockDaily)
        let (_, outName) = try await predictor.ioNames()

        // Restock features need ~28d history; avoid full-collection scans on seeded DBs.
        let featureLookbackDays = 60
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -featureLookbackDays, to: now) ?? now
        let orders = try await app.mongoStore.listOrders(from: from, to: now.addingTimeInterval(1))
        var lag1 = await calculateUsageFromOrders(orders: orders, sku: sku, daysAgo: 1, app: app)
        var lag7 = await calculateUsageFromOrders(orders: orders, sku: sku, daysAgo: 7, app: app)
        var rolling = await calculateRollingUsage(orders: orders, sku: sku, days: 7, app: app)
        let usageSameWeekday28d = await calculateUsageFromOrders(
            orders: orders, sku: sku, daysAgo: 28, app: app)
        let ordersLag1d = calculateOrderCount(orders: orders, daysAgo: 1)
        let itemsLag1d = calculateItemsSold(orders: orders, daysAgo: 1)

        var ys: [Double] = []
        for dayOffset in 0..<horizon {
            let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()

            let inputs: [String: PredictorFeature] = [
                "usage_lag_1d": .double(lag1),
                "sku": .string(sku),
                "day": .int(Calendar.current.component(.day, from: targetDate)),
                "weekday": .int(Calendar.current.component(.weekday, from: targetDate)),
                "month": .int(Calendar.current.component(.month, from: targetDate)),
                "orders_total_lag_1d": .int(ordersLag1d),
                "year": .int(Calendar.current.component(.year, from: targetDate)),
                "usage_lag_7d": .double(lag7),
                "items_total_lag_1d": .double(itemsLag1d),
                "rolling_usage_last_7d": .double(rolling),
                "usage_same_weekday_lag_28d": .double(usageSameWeekday28d),
            ]

            let out = try await predictor.predictMultiple(inputs: inputs, outputName: outName)
            let pred = Double(out.first ?? 0)
            ys.append(pred)
            let rolled = Self.rollFeatures(lag1: lag1, lag7: lag7, rolling: rolling, prediction: pred)
            lag1 = rolled.lag1
            lag7 = rolled.lag7
            rolling = rolled.rolling
        }
        return ys
    }

    /// Recursive lag/rolling update used by multi-step `forecastSeries`.
    static func rollFeatures(
        lag1: Double,
        lag7: Double,
        rolling: Double,
        prediction: Double
    ) -> (lag1: Double, lag7: Double, rolling: Double) {
        _ = lag7
        return (
            lag1: prediction,
            lag7: lag1,
            rolling: (rolling * 6 + prediction) / 7
        )
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
        let rawDemandDuringLead = series
            .prefix(leadTimeDays)
            .map { max(0.0, $0) }
            .reduce(0.0, +)

        // Scale SKU demand by cafe-wide workload outlook vs historical baseline.
        let busynessScale = try await DemandInference.busynessScale(
            app: app, leadTimeDays: leadTimeDays)
        let demandDuringLead = Int((rawDemandDuringLead * busynessScale).rounded())

        // Reorder point (ROP) and whether restock is needed
        let reorderPoint = safetyStockLevel + demandDuringLead
        let needsRestock = currentOnHand <= reorderPoint

        // Reorder quantity:
        // - If parLevel exists: order up to parLevel
        // - Otherwise: order up to reorderPoint
        // Always respect minimumReorderQty and never return negative
        let targetLevel = parLevel ?? reorderPoint
        let reorderQty = max(targetLevel - currentOnHand, minimumReorderQty, 0)
        let unitCost = item.costPerUnitCents
        let predictedSpend = unitCost.map { $0 * reorderQty }

        return RestockDecisionResponse(
            sku: sku,
            needRestock: needsRestock,
            reorderQty: reorderQty,
            reorderPoint: reorderPoint,
            leadTimeDays: leadTimeDays,
            onHand: currentOnHand,
            forecastSumNextLeadTime: demandDuringLead,
            predictedSpendCents: predictedSpend,
            busynessScale: busynessScale,
            unitCostCents: unitCost
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
            app.logger.info("Computing restock decisions for \(items.count) inventory item(s)")
            
            for item in items {
                do {
                    let decision = try await decideRestock(app: app, sku: item.sku, daysAhead: daysAhead)
                    results.append(RestockDecisionWithItem(item: item, decision: decision))
                } catch {
                    app.logger.warning("Restock decision failed for \(item.sku): \(error)")
                }
            }
        } catch {
            app.logger.error("Failed to list inventory for restock decisions: \(error)")
        }
        
        return results
    }

    /// Publish full prediction batch (+ runningLow for items that need restock).
    func publishRestockDecisions(app: Application, daysAhead: Int? = nil) async {
        let results = await computeRestockDecisions(app: app, daysAhead: daysAhead)
        let decisions = results.map(\.decision)
        let need = decisions.filter(\.needRestock).count
        app.logger.info("Publishing \(decisions.count) restock decision(s); needRestock=\(need)")
        if decisions.isEmpty {
            app.logger.warning(
                "No restock predictions to send (empty inventory or every SKU failed). Set SEED_TEST_DATA=true or add inventory."
            )
            return
        }
        await app.realtime.publish(.restockDecisions(decisions), to: .merchant)
        for result in results where result.decision.needRestock {
            await app.realtime.publish(.inventory(.runningLow(result.item)), to: .merchant)
        }
    }

    // MARK: - Server training

    struct TrainRequest: Content {
        var kind: String?
    }

    func capabilities(req: Request) async throws -> PredictorCapabilities {
        await req.application.trainJobs.capabilities(
            workingDirectory: req.application.directory.workingDirectory
        )
    }

    func startTrain(req: Request) async throws -> Response {
        let body = (try? req.content.decode(TrainRequest.self)) ?? TrainRequest(kind: nil)
        let kind = PredictorKind(rawValue: body.kind ?? "restockDaily") ?? .restockDaily
        let runner = req.application.processRunner
        let app = req.application
        let workingDirectory = TrainJobService.normalizedDirectory(app.directory.workingDirectory)
        let scriptPath = TrainJobService.scriptPath(for: kind, workingDirectory: workingDirectory)

        let csvBuilder: @Sendable () async throws -> String
        switch kind {
        case .restockDaily:
            csvBuilder = { try await IngredientDailyCSV.forTraining(store: app.mongoStore) }
        case .workloadHourly:
            csvBuilder = { try await OrdersHourlyCSV.forTraining(store: app.mongoStore) }
        case .reservationsHourly:
            csvBuilder = { try await ReservationsHourlyCSV.forTraining(store: app.mongoStore) }
        case .reservationDuration:
            throw Abort(.badRequest, reason: "Training not wired for reservationDuration")
        }

        let job = try await req.application.trainJobs.start(
            app: app,
            kind: kind,
            runner: runner,
            csvBuilder: csvBuilder,
            scriptPath: scriptPath
        )
        return try Self.jsonResponse(status: .accepted, job)
    }

    func listTrainJobs(req: Request) async throws -> Response {
        let jobs = try await req.application.trainJobs.listJobs(app: req.application, limit: 50)
        return try Self.jsonResponse(status: .ok, TrainJobList(items: jobs))
    }

    func getTrainJob(req: Request) async throws -> Response {
        guard let id = req.parameters.get("jobId"),
              let job = await req.application.trainJobs.getJob(app: req.application, id: id)
        else {
            throw Abort(.notFound, reason: "Training job not found")
        }
        return try Self.jsonResponse(status: .ok, job)
    }

    func autoTrainStatus(req: Request) async throws -> Response {
        let status = await TrainScheduleService.status(app: req.application)
        return try Self.jsonResponse(status: .ok, status)
    }

    private static func jsonResponse<T: Encodable>(status: HTTPStatus, _ value: T) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: "application/json")
        return Response(status: status, headers: headers, body: .init(data: data))
    }

    static func minimalTrainingCSV() -> String {
        let header = [
            "sku", "date", "year", "month", "day", "weekday", "is_weekend",
            "orders_total_lag_1d", "items_total_lag_1d",
            "usage_lag_1d", "usage_lag_7d", "rolling_usage_last_7d",
            "usage_same_weekday_lag_28d",
            "target_usage",
        ].joined(separator: ",")
        var rows = [header]
        for i in 1...20 {
            rows.append(
                "BEANS,2024-01-\(String(format: "%02d", i)),2024,1,\(i),\(i % 7 + 1),0,3,10,2.0,2.5,2.2,2.1,\(Double(i) * 0.5)"
            )
        }
        return rows.joined(separator: "\n") + "\n"
    }
}

// MARK: - Supporting Types
// =======================

/// Response structure for model upload operations
struct ModelUploadResponse: Content, Sendable, BinaryResponseEncodable {
    let id: String
    let filename: String
    let runtime: String
    let bytes: Int
    let storedAt: String
    let kind: String
    let active: Bool

    func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Response structure for restock decisions (wire name matches client)
struct RestockDecisionResponse: Content, Sendable, Equatable, BinaryResponseEncodable {
    var sku: String
    var needRestock: Bool
    var reorderQty: Int
    var reorderPoint: Int
    var leadTimeDays: Int
    var onHand: Int
    var forecastSumNextLeadTime: Int
    /// Optional spend estimate: reorderQty * unitCost when cost is known.
    var predictedSpendCents: Int? = nil
    var busynessScale: Double? = nil
    var unitCostCents: Int? = nil

    func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}


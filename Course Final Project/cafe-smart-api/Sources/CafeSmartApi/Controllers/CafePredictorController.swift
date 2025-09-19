//
//  CafePredictorController.swift
//  CafeSmartApi
//
//  Created by Cole M on 9/2/25.
//
import Vapor
import MongoKitten

#if canImport(CoreML)
struct CafePredictorController {
    struct DayBucket: Hashable {
        let date: Date
        
        init(date: Date) {
            self.date = date
        }
    }
    
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
    
//    http://\(base)/predictor/export?dataset=ingredientDaily&sku=<SKU> (Initial Query is retrieved via ?, additional via &)
    func exportCSV(req: Request) async throws -> Response {
        // Get query parameters
        let qMode = try req.query.get(String.self, at: "dataset")
     /*   let qSku = try? req.query.get(String.self, at: "sku")*/
        
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
    
    struct ModelUploadResponse: Content {
        let id: String
        let filename: String
        let runtime: String
        let bytes: Int
        let storedAt: String
        let kind: String
        let active: Bool
    }
    
    func uploadModel(req: Request) async throws -> ModelUploadResponse {
        
        let qName = try req.query.get(String.self, at: "name")
        let qRuntime = try req.query.get(String.self, at: "runtime")
        let qKind = try req.query.get(String.self, at: "kind")
        
        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "No model data provided")
        }
        
        let providedName = qName.isEmpty == false ? qName : "model.mlmodel"
        
        var filename = providedName
        if !filename.hasSuffix(".mlmodel") {
            filename += ".mlmodel"
        }
        
        filename = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: ".")
        
        let kind = PredictorKind(rawValue: qKind) ?? .restockDaily
        let modelRoot = req.application.directory.workingDirectory + "Models/" + qRuntime + "/" + kind.rawValue + "/"
        try FileManager.default.createDirectory(atPath: modelRoot, withIntermediateDirectories: true)
        let targetPath = modelRoot + filename
        try await req.fileio.writeFile(buffer, at: targetPath)
        
        let attrs = try FileManager.default.attributesOfItem(atPath: targetPath)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? buffer.readableBytes
        
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
            uploadedAt: Date())
        
        try await req.application.mongoStore.createModelArtifact(artifact)
        await req.application.realtimeHub.publish(.modelUploaded(artifact), to: .merchant)
        
        
        // active model
        try await activateModel(req: req, id: artifact._id)
        // instantiate model
        try await instantiateModel(req: req, kind: kind)
        
        let results = await self.computeRestockDecision(app: req.application)
        
        for result in results where result.decision.needRestock {
            await req.application.realtimeHub.publish(.inventory(.runningLow(result.item)), to: .merchant)
        }
     
        return ModelUploadResponse(
            id: artifact._id.hexString,
            filename: filename,
            runtime: qRuntime,
            bytes: size,
            storedAt: targetPath,
            kind: kind.rawValue,
            active: artifact.active)
    }
    
    func activateModel(req: Request, id: ObjectId) async throws {
        try await req.application.mongoStore.setActiveModel(id: id.hexString)
        await req.application.realtimeHub.publish(.modelActivated(kind: .restockDaily, id: id.hexString), to: .merchant)
    }
    
    func instantiateModel(req: Request, kind: PredictorKind) async throws {
#if canImport(CoreML)
        let artifacts = try await req.application.mongoStore.listModelArtifacts()
        guard let artifact = artifacts.first(where: { $0.kind == kind && $0.active }) else {
            throw Abort(.notFound)
        }
        let predictor = try await Predictor(modelPath: artifact.storedAt)
        await req.application.predictors.set(kind: kind, runtime: artifact.runtime, path: artifact.storedAt, predictor: predictor)
        await req.application.realtimeHub.publish(.predictorReady(kind: kind), to: .merchant)
#endif
    }
    
    struct RestockDecisionWithItem {
        let item: InventoryItem
        let decision: RestockDecisionResponse
    }
    
    struct RestockDecisionResponse: Content {
        var sku: String
        var needRestock: Bool
        var reorderQty: Int
        var reorderPoint: Int
        var leadTimeDays: Int
        var onHand: Int
        var forecastSumNextLeadTime: Int
    }
    
    func computeRestockDecision(app: Application, daysAhead: Int? = nil) async -> [RestockDecisionWithItem] {
        var results: [RestockDecisionWithItem] = []
        do {
            let items = try await app.mongoStore.listInventory()
            
            for item in items {
                do {
                    let decision = try await decideRestock(app: app, item: item, daysAhead: daysAhead)
                    results.append(RestockDecisionWithItem(item: item, decision: decision))
                } catch {
                    print("Error processing restock decision for item \(item.sku): \(error)")
                }
            }
        } catch {
            print("Error fetching inventory: \(error)")
        }
        return results
    }
    
    func decideRestock(app: Application, item: InventoryItem, daysAhead: Int?) async throws -> RestockDecisionResponse {
        
        let currentOnHand = item.quantity
        let leadTimeDays = max(1, item.leadTimeDays ?? 3)
        let safetyStockLevel = max(0, item.safetyStock ?? item.reorderThreshold)
        let parLevel = item.parLevel
        let minimumReorderQty = max(0, item.reorderQuantity ?? 0)
        
        var forecastHorizon = max(1, daysAhead ?? leadTimeDays)
        forecastHorizon = min(forecastHorizon, 14)
        
        let series = try await forecastSeries(app: app, horizon: forecastHorizon, item: item)
        
        let demandDuringLead = Int(
            series
                .prefix(leadTimeDays)
                .map { max(0.0, $0) }
                .reduce(0.0, +)
                .rounded())
        
        let reorderPoint = safetyStockLevel + demandDuringLead
        let needsRestock = currentOnHand <= reorderPoint
        
        let targetLevel = parLevel ?? reorderPoint
        let reorderQty = max(targetLevel - currentOnHand, minimumReorderQty, 0)
        
        return RestockDecisionResponse(
            sku: item.sku,
            needRestock: needsRestock,
            reorderQty: reorderQty,
            reorderPoint: reorderPoint,
            leadTimeDays: leadTimeDays,
            onHand: currentOnHand,
            forecastSumNextLeadTime: demandDuringLead)
    }
    

    func requirePredictor(app: Application, _ kind: PredictorKind) async throws -> Predictor {
        guard let predictor = await app.predictors.get(kind) else {
            throw Abort(.failedDependency)
        }
        return predictor
    }
    
    func forecastSeries(app: Application, horizon: Int, item: InventoryItem) async throws -> [Double] {
        let predictor = try await requirePredictor(app: app, .restockDaily)
        let (_, outName) = try await predictor.ioNames()
        
        let orders = try await app.mongoStore.listOrders()
        
        
        var ys: [Double] = []
        for daysOffset in 0..<horizon {
            
            let targetDate = Calendar.current.date(byAdding: .day, value: daysOffset, to: Date()) ?? Date()
            
            //1 day ago
                let usage1DayAgo = await calculateUsageFromOrders(orders: orders, sku: item.sku, daysAgo: 1, app: app)
            //7 days ago
                let usage7DayAgo = await calculateUsageFromOrders(orders: orders, sku: item.sku, daysAgo: 7, app: app)
            //7 days ago for rolling usage
                let usage7DayRollingAvg = await calculateRollingUsage(orders: orders, sku: item.sku, days: 7, app: app)
            //28 days ago
                let usage28DayAgo = await calculateUsageFromOrders(orders: orders, sku: item.sku, daysAgo: 28, app: app)
            
            let ordersLag1Day = calculateOrderCount(orders: orders, daysAgo: 1)
            let itemsLag1Day = calculateItemsSold(orders: orders, daysAgo: 1)
            
            
            let inputs: [String: Any] = [
                "usage_lag_1d": usage1DayAgo,
                "sku": item.sku,
                "day": Calendar.current.component(.day, from: targetDate),
                "weekday": Calendar.current.component(.weekday, from: targetDate),
                "month": Calendar.current.component(.month, from: targetDate),
                "orders_total_lag_1d": ordersLag1Day,
                "year": Calendar.current.component(.year, from: targetDate),
                "usage_lag_7d": usage7DayAgo,
                "items_total_lag_1d": itemsLag1Day,
                "rolling_usage_last_7d": usage7DayRollingAvg,
                "usage_same_weekday_lag_28d": usage28DayAgo
            ]
            
            let out = try await predictor.predictMultiple(inputs: inputs, outputName: outName)
            let first = Double(out.first ?? 0)
            
            ys.append(first)
            
        }
        return ys
    }
    
    func calculateUsageFromOrders(orders: [Order], sku: String, daysAgo: Int, app: Application) async -> Double {
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

    func calculateRollingUsage(orders: [Order], sku: String, days: Int, app: Application) async -> Double {
        var totalUsage: Double = 0
        var validDays = 0
        
        for dayOffset in 1...days {
            let usage = await calculateUsageFromOrders(orders: orders, sku: sku, daysAgo: dayOffset, app: app)
            totalUsage += usage
            validDays += 1
        }
        
        return validDays > 0 ? totalUsage / Double(validDays) : 0.0
    }
    
    func calculateOrderCount(orders: [Order], daysAgo: Int) -> Int {
        let targetDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: targetDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        return orders.filter { order in
            order.createdAt >= startOfDay && order.createdAt < endOfDay
        }.count
    }

    func calculateItemsSold(orders: [Order], daysAgo: Int) -> Double {
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
    
    func calculateOrderUsage(orders: [Order], sku: String, app: Application) async -> Double {
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
    
}


extension Application {
    private struct PredictorRegistryKey: StorageKey {
        typealias Value = PredictorRegistry
    }
    
    /// Access to the predictor registry
    var predictors: PredictorRegistry {
        get {
            storage[PredictorRegistryKey.self] ?? {
                let r = PredictorRegistry();
                storage[PredictorRegistryKey.self] = r;
                return r
            }()
        }
        set { storage[PredictorRegistryKey.self] = newValue }
    }
}

actor PredictorRegistry {
    
    /// Storage for predictor instances
    private var predictors: [PredictorKind: Predictor] = [:]
    
    /// Set a predictor for a specific kind
    func set(kind: PredictorKind, runtime: PredictRuntime, path: String, predictor: Predictor) {
        predictors[kind] = predictor
    }
    
    /// Get a predictor for a specific kind
    func get(_ kind: PredictorKind) -> Predictor? {
        return predictors[kind]
    }
    
    /// Remove a predictor for a specific kind
    func remove(_ kind: PredictorKind) {
        predictors.removeValue(forKey: kind)
    }
    
    /// Clear all predictors
    func clear() {
        predictors.removeAll()
    }
}
#endif

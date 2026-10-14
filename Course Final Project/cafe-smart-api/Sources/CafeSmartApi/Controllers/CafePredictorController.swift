//
//  CafePredictorController.swift
//  CafeSmartApi
//
//  Created by Cole M on 9/2/25.
//
import Vapor
import MongoKitten

struct CafePredictorController {
//    http://\(base)/predictor/export?dataset=ingredientDaily&sku=<SKU> (Initial Query is retrieved via ?, additional via &)
    func exportCSV(req: Request) async throws -> Response {
        let qMode = (try? req.query.get(String.self, at: "dataset"))
            ?? (try? req.query.get(String.self, at: "mode"))
            ?? "ingredientDaily"
        guard qMode == "ingredientDaily" else {
            throw Abort(.badRequest, reason: "Only 'ingredientDaily' mode is supported")
        }
        let skuParam: String? = try? req.query.get(String.self, at: "sku")
        // Same fallback as server train: empty Mongo must still yield a trainable CSV
        // for local Create ML → CoreML.
        let csv = try await IngredientDailyCSV.forTraining(store: req.store, sku: skuParam)
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
        let qName = (try? req.query.get(String.self, at: "name")) ?? ""
        let qRuntime = try? req.query.get(String.self, at: "runtime")
        let qKind = (try? req.query.get(String.self, at: "kind")) ?? "restockDaily"

        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "No model data provided")
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
        let modelRoot = ModelUploadSupport.modelsRoot(
            workingDirectory: req.application.directory.workingDirectory,
            runtime: runtime,
            kind: kind
        )
        try FileManager.default.createDirectory(atPath: modelRoot, withIntermediateDirectories: true)
        let targetPath = modelRoot + filename
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
            uploadedAt: Date())

        try await req.application.mongoStore.createModelArtifact(artifact)
        await req.application.realtimeHub.publish(.modelUploaded(artifact), to: .merchant)

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
            active: true)
    }

    func listModels(req: Request) async throws -> ModelsList {
        let result = try await req.application.mongoStore.listModelArtifacts()
        return ModelsList(items: result)
    }

    func activateModel(req: Request) async throws -> HTTPStatus {
        struct Activate: Content {
            var id: String
        }
        let body = try req.content.decode(Activate.self)
        guard !body.id.isEmpty else { throw Abort(.badRequest) }
        try await activateModel(req: req, id: body.id)
        return .ok
    }

    func deleteModel(req: Request) async throws -> HTTPStatus {
        struct DeleteBody: Content {
            var id: String
        }
        let body = try req.content.decode(DeleteBody.self)
        guard !body.id.isEmpty else { throw Abort(.badRequest) }
        try await ModelArtifactLifecycle.deleteInactive(app: req.application, id: body.id)
        return .ok
    }
    
    func activateModel(req: Request, id: String) async throws {
        guard try await req.application.mongoStore.findModelArtifact(by: id) != nil else {
            throw Abort(.notFound, reason: "Model artifact not found")
        }
        try await req.application.mongoStore.setActiveModel(id: id)
        let artifact = try await req.application.mongoStore.findModelArtifact(by: id)!
        await req.application.realtimeHub.publish(.modelActivated(kind: artifact.kind, id: id), to: .merchant)
        try await instantiateModel(req: req, kind: artifact.kind)
    }

    func instantiatePredictor(req: Request) async throws -> HTTPStatus {
        struct Body: Content {
            var kind: String
        }
        let body = try req.content.decode(Body.self)
        let normalized = body.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = PredictorKind.allCases.first(where: {
            $0.rawValue.lowercased() == normalized.lowercased()
        }) else {
            throw Abort(.badRequest)
        }
        try await instantiateModel(req: req, kind: kind)
        return .ok
    }
    
    func instantiateModel(req: Request, kind: PredictorKind) async throws {
        let artifacts = try await req.application.mongoStore.listModelArtifacts()
        guard let artifact = artifacts.first(where: { $0.kind == kind && $0.active }) else {
            throw Abort(.notFound)
        }
        let predictor: any PredictorServing
        do {
            predictor = try await PredictorFactory.make(runtime: artifact.runtime, path: artifact.storedAt)
        } catch let error as PredictorError {
            throw Abort(.failedDependency, reason: error.description)
        }
        await req.application.predictors.set(kind: kind, runtime: artifact.runtime, path: artifact.storedAt, predictor: predictor)
        await req.application.realtimeHub.publish(.predictorReady(kind: kind), to: .merchant)
    }
    
    struct RestockDecisionWithItem {
        let item: InventoryItem
        let decision: RestockDecisionResponse
    }
    
    struct RestockDecisionResponse: Content, Sendable, Equatable {
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
            app.logger.info("Computing restock decisions for \(items.count) inventory item(s)")
            
            for item in items {
                do {
                    let decision = try await decideRestock(app: app, item: item, daysAhead: daysAhead)
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

    func publishRestockDecisions(app: Application, daysAhead: Int? = nil) async {
        let results = await computeRestockDecision(app: app, daysAhead: daysAhead)
        let decisions = results.map(\.decision)
        let need = decisions.filter(\.needRestock).count
        app.logger.info("Publishing \(decisions.count) restock decision(s); needRestock=\(need)")
        if decisions.isEmpty {
            app.logger.warning(
                "No restock predictions to send (empty inventory or every SKU failed). Set SEED_TEST_DATA=true or add inventory."
            )
            return
        }
        await app.realtimeHub.publish(.restockDecisions(decisions), to: .merchant)
        for result in results where result.decision.needRestock {
            await app.realtimeHub.publish(.inventory(.runningLow(result.item)), to: .merchant)
        }
    }
    
    struct RestockDecisionRequest: Content {
        var sku: String
        var daysAhead: Int?
    }

    func decideRestock(req: Request) async throws -> RestockDecisionResponse {
        let body = try req.content.decode(RestockDecisionRequest.self)
        let items = try await req.application.mongoStore.listInventory()
        guard let item = items.first(where: { $0.sku == body.sku }) else {
            throw Abort(.notFound, reason: "Inventory item not found for sku")
        }
        return try await decideRestock(app: req.application, item: item, daysAhead: body.daysAhead)
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
    

    func requirePredictor(app: Application, _ kind: PredictorKind) async throws -> any PredictorServing {
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
            
            
            let inputs: [String: PredictorFeature] = [
                "usage_lag_1d": .double(usage1DayAgo),
                "sku": .string(item.sku),
                "day": .int(Calendar.current.component(.day, from: targetDate)),
                "weekday": .int(Calendar.current.component(.weekday, from: targetDate)),
                "month": .int(Calendar.current.component(.month, from: targetDate)),
                "orders_total_lag_1d": .int(ordersLag1Day),
                "year": .int(Calendar.current.component(.year, from: targetDate)),
                "usage_lag_7d": .double(usage7DayAgo),
                "items_total_lag_1d": .double(itemsLag1Day),
                "rolling_usage_last_7d": .double(usage7DayRollingAvg),
                "usage_same_weekday_lag_28d": .double(usage28DayAgo),
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
        let app = req.application
        let job = try await app.trainJobs.start(
            app: app,
            kind: kind,
            runner: app.processRunner,
            csvBuilder: {
                try await IngredientDailyCSV.forTraining(store: app.mongoStore)
            }
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

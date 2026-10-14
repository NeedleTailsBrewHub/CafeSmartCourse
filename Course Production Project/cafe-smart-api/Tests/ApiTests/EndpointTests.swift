import Foundation
import Testing
import Vapor
import BinaryCodable
import BSON
import MongoKitten
import NIO
import NIOHTTP1
@testable import cafe_smart_api


@Suite(.serialized)
struct EndpointTests {

    private func makeApp(adminEmail: String? = nil) async throws -> Application {
        try await APITestHelpers.makeApp(adminEmail: adminEmail ?? "endpoint-anon@example.com")
    }

    private func shutdownApp(_ app: Application) async throws {
        try await APITestHelpers.shutdownApp(app)
    }

    private func cmkWSPort(_ app: Application) async throws -> Int {
        guard let port = await app.realtime.boundPort else {
            Issue.record("CMK WebSocket server did not bind a port")
            throw Abort(.internalServerError)
        }
        return port
    }

    @Test func predictorModelLifecycleAndForecastEndpoints() async throws {
        let adminEmail = "admin12@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

            // List models (empty in test store)
            var res = try await request(app, .GET, "/api/auth/predictor/models", token: adminToken)
            #expect(res.status == .ok)
            let models = try decodeBody(ModelsList.self, from: res)
            #expect(models.items.isEmpty)

            // Activate unknown id → 404
            struct ActivateReq: Content { let id: String }
            res = try await request(app, .POST, "/api/auth/predictor/models/activate", token: adminToken, bson: ActivateReq(id: ObjectId().hexString))
            #expect(res.status == .notFound)

            // Instantiate without an active artifact should 404
            struct InstReq: Content { let kind: String }
            res = try await request(app, .POST, "/api/auth/predictor/instantiate", token: adminToken, bson: InstReq(kind: "restockDaily"))
            #expect(res.status == .notFound)

            // Seed inventory and exercise restock decide (testing uses synthetic forecast ramp)
            struct InvCreate: Content {
                let sku: String; let name: String; let quantity: Int
                let reorderThreshold: Int; let unit: String; let supplier: String?
            }
            res = try await request(
                app, .POST, "/api/auth/inventory", token: adminToken,
                bson: InvCreate(sku: "BEANS-API-1KG", name: "Beans", quantity: 10, reorderThreshold: 5, unit: "bag", supplier: nil))
            #expect(res.status == .ok || res.status == .created)

            struct DecideReq: Content { let sku: String; let daysAhead: Int? }
            res = try await request(
                app, .POST, "/api/auth/predictor/restock/decide", token: adminToken,
                bson: DecideReq(sku: "BEANS-API-1KG", daysAhead: 7))
            #expect(res.status == .ok)
            let decision = try decodeBody(RestockDecisionResponse.self, from: res)
            #expect(decision.sku == "BEANS-API-1KG")
            #expect(decision.leadTimeDays == 3)

            // Export CSV (ingredientDaily)
            res = try await request(app, .GET, "/api/auth/predictor/export", token: adminToken)
            #expect(res.status == .ok)
            #expect(res.headers[.contentType].first?.contains("text/csv") == true)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func predictorDeleteActivateAndTrainHistoryHTTP() async throws {
        let adminEmail = "admin-ml-http@example.com"
        let trainerPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("cafesmart-trainer-http-\(UUID().uuidString).py").path
        try "# test\n".write(toFile: trainerPath, atomically: true, encoding: .utf8)
        setenv("TRAINER_SCRIPT", trainerPath, 1)
        defer {
            unsetenv("TRAINER_SCRIPT")
            try? FileManager.default.removeItem(atPath: trainerPath)
        }

        let app = try await makeApp(adminEmail: adminEmail)
        app.processRunner = FakeProcessRunner(exitCode: 0, writeEmptyOutFile: true)
        do {
            let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

            struct IdBody: Content { let id: String }
            struct TrainBody: Content { let kind: String }

            // Seed active + inactive artifacts on disk
            let activePath = FileManager.default.temporaryDirectory
                .appendingPathComponent("http-active-\(UUID().uuidString).onnx").path
            let inactivePath = FileManager.default.temporaryDirectory
                .appendingPathComponent("http-inactive-\(UUID().uuidString).onnx").path
            FileManager.default.createFile(atPath: activePath, contents: Data([0x01]), attributes: nil)
            FileManager.default.createFile(atPath: inactivePath, contents: Data([0x01]), attributes: nil)
            defer {
                try? FileManager.default.removeItem(atPath: activePath)
                try? FileManager.default.removeItem(atPath: inactivePath)
            }
            let activeId = ObjectId().hexString
            let inactiveId = ObjectId().hexString
            try await app.mongoStore.createModelArtifact(MLModelArtifact(
                _id: activeId, id: activeId, filename: "active.onnx", runtime: .onnx, kind: .restockDaily,
                storedAt: activePath, bytes: 1, active: true, uploadedAt: Date()
            ))
            try await app.mongoStore.createModelArtifact(MLModelArtifact(
                _id: inactiveId, id: inactiveId, filename: "inactive.onnx", runtime: .onnx, kind: .restockDaily,
                storedAt: inactivePath, bytes: 1, active: false, uploadedAt: Date().addingTimeInterval(-60)
            ))

            // Delete active → 409
            var res = try await request(
                app, .POST, "/api/auth/predictor/models/delete", token: adminToken, bson: IdBody(id: activeId))
            #expect(res.status == .conflict)

            // Activate inactive → loads registry
            res = try await request(
                app, .POST, "/api/auth/predictor/models/activate", token: adminToken, bson: IdBody(id: inactiveId))
            #expect(res.status == .ok)
            #expect(await app.predictors.get(.restockDaily) != nil)
            let afterActivate = try await app.mongoStore.findModelArtifact(by: inactiveId)
            #expect(afterActivate?.active == true)

            // Delete former active (now inactive) → 200 and removed
            res = try await request(
                app, .POST, "/api/auth/predictor/models/delete", token: adminToken, bson: IdBody(id: activeId))
            #expect(res.status == .ok)
            #expect(try await app.mongoStore.findModelArtifact(by: activeId) == nil)

            // Train via HTTP, then list history
            res = try await request(
                app, .POST, "/api/auth/predictor/train", token: adminToken, bson: TrainBody(kind: "restockDaily"))
            #expect(res.status == .accepted)
            let started = try decodeJSONBody(TrainJob.self, from: res)
            #expect(!started.id.isEmpty)

            var finished: TrainJob?
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(50))
                if let j = await app.trainJobs.getJob(started.id), j.status == .succeeded || j.status == .failed {
                    finished = j
                    break
                }
            }
            #expect(finished?.status == .succeeded)

            res = try await request(app, .GET, "/api/auth/predictor/train", token: adminToken)
            #expect(res.status == .ok)
            let history = try decodeJSONBody(TrainJobList.self, from: res)
            #expect(history.items.contains(where: { $0.id == started.id }))
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    private func request(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        if let token {
            req.headers.bearerAuthorization = .init(token: token)
        }
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }

    private func request<T: Content>(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        bson: T
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        // Use JSON for in-process request bodies. BinaryCodable's ContentEncoder
        // path currently leaves POSTs unauthenticated under Vapor's test responder
        // (Authorization is present but middleware still returns 401). Responses
        // remain BinaryCodable via Accept.
        try req.content.encode(bson, as: .json)
        if let token {
            req.headers.bearerAuthorization = .init(token: token)
        }
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }

    private func registerAndLogin(app: Application, email: String, password: String, name: String? = nil, isAdmin: Bool = true) async throws -> (user: UserPublic, token: String, refreshToken: String?) {
        struct RegisterRequest: Content {
            let email: String
            let password: String
            let name: String?
            let isAdmin: Bool
        }
        let register = RegisterRequest(email: email, password: password, name: name, isAdmin: isAdmin)
        _ = try await request(app, .POST, "/api/register", bson: register)

        struct LoginRequest: Content { let email: String; let password: String }
        struct TokenResponse: Content { let token: String; let refreshToken: String?; let expiresAt: Date; let user: UserPublic }
        let loginReq = LoginRequest(email: email, password: password)
        let res = try await request(app, .POST, "/api/login", bson: loginReq)
        #expect(res.status == .ok)
        let body = try decodeBody(TokenResponse.self, from: res)
        return (body.user, body.token, body.refreshToken)
    }

    private func responseData(_ response: Response) -> Data {
        var buffer = response.body.buffer ?? ByteBuffer()
        return Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
    }

    private func decodeBody<T: Decodable>(_ type: T.Type, from response: Response) throws -> T {
        try BinaryDecoder().decode(type, from: responseData(response))
    }

    private func decodeJSONBody<T: Decodable>(_ type: T.Type, from response: Response) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: responseData(response))
    }

    // MARK: Tests

    @Test func authRegisterLoginRefresh() async throws {
        let app = try await makeApp()

        let (user, token, refreshToken) = try await registerAndLogin(app: app, email: "user@example.com", password: "password123", name: "Test User")
        #expect(user.email == "user@example.com")
        #expect(!token.isEmpty)
        #expect(refreshToken != nil)

        struct TokenResponse: Content { let token: String; let expiresAt: Date; let user: UserPublic }
        let refresh = try await request(app, .POST, "/api/auth/refresh", token: refreshToken)
        #expect(refresh.status == .ok)
        let refreshed = try decodeBody(TokenResponse.self, from: refresh)
        #expect(!refreshed.token.isEmpty)

        try await shutdownApp(app)
    }

    @Test func menuCrudWithAdmin() async throws {
        let adminEmail = "admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct Create: Content { let name: String; let description: String?; let priceCents: Int; let isAvailable: Bool; let category: String? }
        let create = Create(name: "Latte", description: "Milk", priceCents: 499, isAvailable: true, category: "Drinks")
        var res = try await request(app, .POST, "/api/auth/menu", token: adminToken, bson: create)
        #expect(res.status == .ok || res.status == .created)

        res = try await request(app, .GET, "/api/auth/menu", token: adminToken)
        #expect(res.status == .ok)
        let list = try decodeBody(PaginatedMenuItems.self, from: res).items
        #expect(list.count == 1)
        guard let item = list.first else {
            Issue.record("Expected a created menu item")
            try await shutdownApp(app)
            return
        }

        // GET by id
        res = try await request(app, .GET, "/api/auth/menu/\(item.id)", token: adminToken)
        #expect(res.status == .ok)

        struct Update: Content { let name: String?; let description: String?; let priceCents: Int?; let isAvailable: Bool?; let category: String? }
        let update = Update(name: "Iced Latte", description: nil, priceCents: 599, isAvailable: nil, category: nil)
        res = try await request(app, .PUT, "/api/auth/menu/\(item.id)", token: adminToken, bson: update)
        #expect(res.status == .ok)
        let updated = try decodeBody(MenuItem.self, from: res)
        #expect(updated.name == "Iced Latte")
        #expect(updated.priceCents == 599)

        res = try await request(app, .DELETE, "/api/auth/menu/\(item.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await shutdownApp(app)
    }

    @Test func ordersFlowUserAndAdmin() async throws {
        let adminEmail = "admin2@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        let (_, userToken, _) = try await registerAndLogin(app: app, email: "user2@example.com", password: "password123")
        let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct OrderItemReq: Content { let menuItemId: String; let quantity: Int; let notes: String? }
        struct OrderCreateReq: Content { let customerName: String?; let items: [OrderItemReq]; let pickupTime: Date? }
        let body = OrderCreateReq(customerName: "Bob", items: [OrderItemReq(menuItemId: "sku-1", quantity: 2, notes: nil)], pickupTime: nil)
        var res = try await request(app, .POST, "/api/auth/orders", token: userToken, bson: body)
        #expect(res.status == .ok || res.status == .created)
        let order = try decodeBody(Order.self, from: res)

        // GET list
        res = try await request(app, .GET, "/api/auth/orders", token: userToken)
        #expect(res.status == .ok)
        let list = try decodeBody(PaginatedOrders.self, from: res).items
        #expect(list.count == 1)

        // GET by id
        res = try await request(app, .GET, "/api/auth/orders/\(order.id)", token: userToken)
        #expect(res.status == .ok)

        struct StatusUpdate: Content { let status: OrderStatus }
        res = try await request(app, .PUT, "/api/auth/orders/\(order.id)/status", token: adminToken, bson: StatusUpdate(status: .completed))
        #expect(res.status == .ok)
        let updated = try decodeBody(Order.self, from: res)
        #expect(updated.status == .completed)

        res = try await request(app, .DELETE, "/api/auth/orders/\(order.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await shutdownApp(app)
    }

    @Test func reservationsFlowUserAndAdminDelete() async throws {
        let adminEmail = "admin3@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        let (_, userToken, _) = try await registerAndLogin(app: app, email: "user3@example.com", password: "password123")
        let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct ReservationCreateReq: Content { let name: String; let partySize: Int; let startTime: Date; let phone: String?; let notes: String? }
        let now = Date().addingTimeInterval(3600)
        let body = ReservationCreateReq(name: "Alice", partySize: 4, startTime: now, phone: nil, notes: nil)
        var res = try await request(app, .POST, "/api/auth/reservations", token: userToken, bson: body)
        #expect(res.status == .ok || res.status == .created)
        let created = try decodeBody(Reservation.self, from: res)

        // GET list
        res = try await request(app, .GET, "/api/auth/reservations", token: userToken)
        #expect(res.status == .ok)
        let list = try decodeBody(PaginatedReservations.self, from: res).items
        #expect(list.count == 1)

        // GET by id
        res = try await request(app, .GET, "/api/auth/reservations/\(created.id)", token: userToken)
        #expect(res.status == .ok)

        res = try await request(app, .DELETE, "/api/auth/reservations/\(created.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await shutdownApp(app)
    }

    @Test func inventoryCrudAdminOnly() async throws {
        let adminEmail = "admin4@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct Create: Content { let sku: String; let name: String; let quantity: Int; let reorderThreshold: Int; let unit: String; let supplier: String? }
        let create = Create(sku: "SKU-1", name: "Beans", quantity: 10, reorderThreshold: 5, unit: "bag", supplier: nil)
        var res = try await request(app, .POST, "/api/auth/inventory", token: adminToken, bson: create)
        #expect(res.status == .ok || res.status == .created)

        // GET list
        res = try await request(app, .GET, "/api/auth/inventory", token: adminToken)
        #expect(res.status == .ok)
        let list = try decodeBody(PaginatedInventoryItems.self, from: res).items
        #expect(list.count == 1)
        guard let item = list.first else {
            Issue.record("Expected a created inventory item")
            try await shutdownApp(app)
            return
        }

        // GET by id
        res = try await request(app, .GET, "/api/auth/inventory/\(item.id)", token: adminToken)
        #expect(res.status == .ok)

        struct Update: Content { let name: String?; let quantity: Int?; let reorderThreshold: Int?; let unit: String?; let supplier: String? }
        let update = Update(name: "Premium Beans", quantity: 12, reorderThreshold: nil, unit: nil, supplier: nil)
        res = try await request(app, .PUT, "/api/auth/inventory/\(item.id)", token: adminToken, bson: update)
        #expect(res.status == .ok)
        let updated = try decodeBody(InventoryItem.self, from: res)
        #expect(updated.name == "Premium Beans")
        #expect(updated.quantity == 12)

        res = try await request(app, .DELETE, "/api/auth/inventory/\(item.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await shutdownApp(app)
    }

    @Test func loyaltyAndPredictorEndpoints() async throws {
        let adminEmail = "admin5@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (user, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct Enroll: Content { let userId: String }
        var res = try await request(app, .POST, "/api/auth/loyalty/enroll", token: adminToken, bson: Enroll(userId: user.id))
        #expect(res.status == .ok)

        // GET loyalty account by id should succeed
        struct LoyaltyAccountPublic: Content { let id: String; let userId: String; let points: Int; let tier: String }
        let enrolled = try decodeBody(LoyaltyAccountPublic.self, from: res)
        res = try await request(app, .GET, "/api/auth/loyalty/\(enrolled.id)", token: adminToken)
        #expect(res.status == .ok)

        struct Accrue: Content { let userId: String; let points: Int }
        res = try await request(app, .POST, "/api/auth/loyalty/accrue", token: adminToken, bson: Accrue(userId: user.id, points: 120))
        #expect(res.status == .ok)

        struct Redeem: Content { let userId: String; let points: Int }
        res = try await request(app, .POST, "/api/auth/loyalty/redeem", token: adminToken, bson: Redeem(userId: user.id, points: 20))
        #expect(res.status == .ok)

        // Redeem too many points should fail with 400
        res = try await request(app, .POST, "/api/auth/loyalty/redeem", token: adminToken, bson: Redeem(userId: user.id, points: 999_999))
        #expect(res.status == .badRequest)

        // Export CSV should return text/csv
        res = try await request(app, .GET, "/api/auth/predictor/export", token: adminToken)
        #expect(res.status == .ok)
        #expect(res.headers[.contentType].first?.contains("text/csv") == true)

        try await shutdownApp(app)
    }

    @Test func recipesCrudAndListByMenuItem() async throws {
        let adminEmail = "admin6@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Create a menu item to attach a recipe to
        struct MenuCreate: Content { let name: String; let description: String?; let priceCents: Int; let isAvailable: Bool; let category: String? }
        let mc = MenuCreate(name: "Cappuccino", description: nil, priceCents: 399, isAvailable: true, category: "Drinks")
        var res = try await request(app, .POST, "/api/auth/menu", token: adminToken, bson: mc)
        #expect(res.status == .ok || res.status == .created)
        let createdItem = try decodeBody(MenuItem.self, from: res)

        // Create a recipe
        let comps = [RecipeComponent(sku: "BEANS", unitsPerItem: 18.0, wastageRate: 0.05), RecipeComponent(sku: "MILK", unitsPerItem: 160.0, wastageRate: nil)]
        let rc = CreateRecipeRequest(menuItemId: createdItem.id, components: comps)
        res = try await request(app, .POST, "/api/auth/recipes", token: adminToken, bson: rc)
        #expect(res.status == .ok || res.status == .created)
        let recipe = try decodeBody(Recipe.self, from: res)

        // List recipes
        res = try await request(app, .GET, "/api/auth/recipes", token: adminToken)
        #expect(res.status == .ok)
        let recipes = try decodeBody(RecipesWrapper.self, from: res).items
        #expect(recipes.count == 1)

        // Get by id
        res = try await request(app, .GET, "/api/auth/recipes/\(recipe.id)", token: adminToken)
        #expect(res.status == .ok)

        // List for menu item
        res = try await request(app, .GET, "/api/auth/menu/\(createdItem.id)/recipes", token: adminToken)
        #expect(res.status == .ok)
        let forItem = try decodeBody(RecipesWrapper.self, from: res).items
        #expect(forItem.count == 1)

        // Update recipe components
        let updatedComps = [RecipeComponent(sku: "BEANS", unitsPerItem: 20.0, wastageRate: 0.05)]
        res = try await request(app, .PUT, "/api/auth/recipes/\(recipe.id)", token: adminToken, bson: UpdateRecipeRequest(components: updatedComps))
        #expect(res.status == .ok)

        // Delete
        res = try await request(app, .DELETE, "/api/auth/recipes/\(recipe.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await shutdownApp(app)
    }

    @Test func seatingAreasAndTablesCrudWithCascade() async throws {
        let adminEmail = "admin7@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Create area
        var res = try await request(
            app, .POST, "/api/auth/seating/areas", token: adminToken,
            bson: CreateSeatingAreaRequest(name: "Main Hall", defaultTurnMinutes: 90, active: true))
        #expect(res.status == .ok || res.status == .created)
        let area = try decodeBody(SeatingArea.self, from: res)

        // List areas
        res = try await request(app, .GET, "/api/auth/seating/areas", token: adminToken)
        #expect(res.status == .ok)

        // Create table
        res = try await request(
            app, .POST, "/api/auth/seating/tables", token: adminToken,
            bson: CreateCafeTableRequest(
                areaId: area.id, name: "T1", capacity: 2, accessible: false, highTop: nil,
                outside: nil, active: true))
        #expect(res.status == .ok || res.status == .created)
        let table = try decodeBody(CafeTable.self, from: res)

        // Get area by id
        res = try await request(app, .GET, "/api/auth/seating/areas/\(area.id)", token: adminToken)
        #expect(res.status == .ok)

        // List tables in area
        res = try await request(app, .GET, "/api/auth/seating/areas/\(area.id)/tables", token: adminToken)
        #expect(res.status == .ok)
        var tables = try decodeBody(TablesWrapper.self, from: res).items
        #expect(tables.count == 1)

        // List all tables
        res = try await request(app, .GET, "/api/auth/seating/tables", token: adminToken)
        #expect(res.status == .ok)

        // Get table by id
        res = try await request(app, .GET, "/api/auth/seating/tables/\(table.id)", token: adminToken)
        #expect(res.status == .ok)

        // Update table
        res = try await request(
            app, .PUT, "/api/auth/seating/tables/\(table.id)", token: adminToken,
            bson: UpdateCafeTableRequest(name: "T1-Window", capacity: 3))
        #expect(res.status == .ok)

        // Cascade: delete area should remove tables
        res = try await request(app, .DELETE, "/api/auth/seating/areas/\(area.id)", token: adminToken)
        #expect(res.status == .noContent)
        res = try await request(app, .GET, "/api/auth/seating/areas/\(area.id)/tables", token: adminToken)
        #expect(res.status == .ok)
        tables = try decodeBody(TablesWrapper.self, from: res).items
        #expect(tables.count == 0)

        try await shutdownApp(app)
    }

    @Test func businessConfigUpsertAndGet() async throws {
        let adminEmail = "admin8@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken, _) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Unauthorized without token
        var res = try await request(app, .GET, "/api/auth/config")
        #expect(res.status == .unauthorized)

        // Upsert (create or replace)
        let hours: [BusinessHours] = [BusinessHours(weekday: 2, open: "07:00", close: "19:00"), BusinessHours(weekday: 3, open: "07:00", close: "19:00")]
        let staffing = StaffingRules(ordersPerBaristaPerHour: 40, ordersPerBakerPerHour: 30, guestsPerHostPerHour: 50)
        let cfg = BusinessConfig(id: ObjectId().hexString, timezone: "America/New_York", hours: hours, seatingCapacity: 45, staffing: staffing)
        res = try await request(app, .PUT, "/api/auth/config", token: adminToken, bson: cfg)
        #expect(res.status == .ok)

        // Get should return the upserted config
        res = try await request(app, .GET, "/api/auth/config", token: adminToken)
        #expect(res.status == .ok)
        let fetched = try decodeBody(BusinessConfig.self, from: res)
        #expect(fetched.timezone == "America/New_York")

        try await shutdownApp(app)
    }

    // MARK: WebSocket / CMK Tests
    //
    // Live WebSocketKit peers hang under SwiftPM (connect is not cancelable and can
    // outlive task-group timeouts). Cover CMK wiring + auth packet contract in-process.

    @Test func websocketHubStartsStopsAndPublishes() async throws {
        let app = try await makeApp()
        let port = try await cmkWSPort(app)
        #expect(port > 0)
        await app.realtime.publish(.none, to: .merchant)
        await app.realtime.publish(.none, to: .customer)
        try await shutdownApp(app)
        #expect(await app.realtime.boundPort == nil)
    }

    @Test func websocketAuthPacketRoundTrips() async throws {
        let app = try await makeApp()
        let packet = WSAuthPacket(token: "test.jwt.token", topic: "merchant")
        let encoded = try BinaryEncoder().encode(packet)
        let decoded = try BinaryDecoder().decode(WSAuthPacket.self, from: encoded)
        #expect(decoded.token == packet.token)
        #expect(decoded.topic == "merchant")
        try await shutdownApp(app)
    }

    @Test func websocketMessagePacketRoundTrips() async throws {
        let app = try await makeApp()
        let item = InventoryItem(
            id: ObjectId().hexString, sku: "SKU-INV", name: "Milk",
            quantity: 5, reorderThreshold: 2, unit: "L", supplier: nil)
        let packet = RealtimeHub.MessagePacket.inventory(.restocked(item))
        let encoded = try BinaryEncoder().encode(packet)
        let decoded = try BinaryDecoder().decode(RealtimeHub.MessagePacket.self, from: encoded)
        guard case .inventory(.restocked(let rec)) = decoded else {
            Issue.record("Unexpected packet \(decoded)")
            try await shutdownApp(app)
            return
        }
        #expect(rec.sku == "SKU-INV")
        try await shutdownApp(app)
    }

    @Test func userAccountEndpointsLogoutUpdatePasswordDeleteAccount() async throws {
        let app = try await makeApp()
        let email = "acct@example.com"
        let originalPassword = "password123"
        struct TokenResponse: Content { let token: String; let refreshToken: String?; let expiresAt: Date; let user: UserPublic }

        // Register and login
        let (_, token, _) = try await registerAndLogin(app: app, email: email, password: originalPassword)

        // Logout should succeed
        var res = try await request(app, .POST, "/api/auth/logout", token: token)
        #expect(res.status == .ok)

        // Update password
        struct UpdatePasswordReq: Content { let oldPassword: String; let newPassword: String }
        let newPassword = "newPassword456"
        res = try await request(app, .PUT, "/api/auth/update-password", token: token, bson: UpdatePasswordReq(oldPassword: originalPassword, newPassword: newPassword))
        #expect(res.status == .ok)

        // Login with old password should fail
        struct LoginRequest: Content { let email: String; let password: String }
        res = try await request(app, .POST, "/api/login", bson: LoginRequest(email: email, password: originalPassword))
        #expect(res.status == .unauthorized)

        // Login with new password should succeed
        res = try await request(app, .POST, "/api/login", bson: LoginRequest(email: email, password: newPassword))
        #expect(res.status == .ok)

        // Delete account
        let res2 = try await request(app, .POST, "/api/login", bson: LoginRequest(email: email, password: newPassword))
        #expect(res2.status == .ok)
        let tokenRes = try decodeBody(TokenResponse.self, from: res2)
        let del = try await request(app, .DELETE, "/api/auth/account", token: tokenRes.token)
        #expect(del.status == .noContent)

        // Login should now fail
        let afterDel = try await request(app, .POST, "/api/login", bson: LoginRequest(email: email, password: newPassword))
        #expect(afterDel.status == .unauthorized)

        try await shutdownApp(app)
    }

    @Test func inventoryAuthRequirements() async throws {
        let adminEmail = "admin9@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        // Without token => 401
        var res = try await request(app, .GET, "/api/auth/inventory")
        #expect(res.status == .unauthorized)

        // With non-admin token => custom 995 code
        let (_, userToken, _) = try await registerAndLogin(app: app, email: "notadmin@example.com", password: "password123", isAdmin: false)
        res = try await request(app, .GET, "/api/auth/inventory", token: userToken)
        #expect(res.status.code == 995)

        try await shutdownApp(app)
    }

    @Test func ordersCreateValidatesItems() async throws {
        let app = try await makeApp()
        let (_, token, _) = try await registerAndLogin(app: app, email: "orderfail@example.com", password: "password123")

        struct OrderItemReq: Content { let menuItemId: String; let quantity: Int; let notes: String? }
        struct OrderCreateReq: Content { let customerName: String?; let items: [OrderItemReq]; let pickupTime: Date? }
        let bad = OrderCreateReq(customerName: "Bob", items: [], pickupTime: nil)
        let res = try await request(app, .POST, "/api/auth/orders", token: token, bson: bad)
        #expect(res.status == .badRequest)

        try await shutdownApp(app)
    }

    @Test func defaultBodySizeIsOneMegabyte() async throws {
        let app = try await makeApp()
        #expect(app.routes.defaultMaxBodySize == "1mb")
        try await shutdownApp(app)
    }

    @Test func mlModelArtifactWireUsesStringIds() async throws {
        let app = try await makeApp()
        let id = ObjectId().hexString
        let artifact = MLModelArtifact(
            _id: id,
            id: id,
            filename: "model.mlmodel",
            runtime: .coreml,
            kind: .restockDaily,
            storedAt: "/tmp/model.mlmodel",
            bytes: 12,
            active: false,
            uploadedAt: Date()
        )
        let encoded = try BinaryEncoder().encode(artifact)
        let decoded = try BinaryDecoder().decode(MLModelArtifact.self, from: encoded)
        #expect(decoded._id == id)
        #expect(decoded.id == id)
        try await shutdownApp(app)
    }
}




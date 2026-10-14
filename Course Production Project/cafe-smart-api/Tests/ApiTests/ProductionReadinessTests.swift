//
//  ProductionReadinessTests.swift
//  ApiTests
//
//  Coverage for Menu CMS, order ownership, customer cancel rules,
//  DEBUG seed, reservations, and loyalty lookup by userId.
//

import BinaryCodable
import Foundation
import NIO
import NIOHTTP1
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct ProductionReadinessTests {

    // MARK: - Helpers

    private func makeApp(adminEmail: String) async throws -> Application {
        try await APITestHelpers.makeApp(adminEmail: adminEmail)
    }

    private func shutdownApp(_ app: Application) async throws {
        try await APITestHelpers.shutdownApp(app)
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
        body: T
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        try req.content.encode(body, as: .json)
        if let token {
            req.headers.bearerAuthorization = .init(token: token)
        }
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }

    private func registerAndLogin(
        app: Application,
        email: String,
        password: String = "password123",
        name: String? = nil,
        requestAdmin: Bool = false
    ) async throws -> (user: UserPublic, token: String) {
        struct RegisterRequest: Content {
            let email: String
            let password: String
            let name: String?
            let isAdmin: Bool
        }
        _ = try await request(
            app, .POST, "/api/register",
            body: RegisterRequest(email: email, password: password, name: name, isAdmin: requestAdmin))

        struct LoginRequest: Content { let email: String; let password: String }
        struct TokenResponse: Content {
            let token: String
            let refreshToken: String?
            let expiresAt: Date
            let user: UserPublic
        }
        let res = try await request(
            app, .POST, "/api/login",
            body: LoginRequest(email: email, password: password))
        #expect(res.status == .ok)
        let body = try decodeBody(TokenResponse.self, from: res)
        return (body.user, body.token)
    }

    private func responseData(_ response: Response) -> Data {
        var buffer = response.body.buffer ?? ByteBuffer()
        return Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
    }

    private func decodeBody<T: Decodable>(_ type: T.Type, from response: Response) throws -> T {
        try BinaryDecoder().decode(type, from: responseData(response))
    }

    /// AdminMiddleware returns custom 995 when the caller is authenticated but not admin.
    private func isAdminDenied(_ status: HTTPStatus) -> Bool {
        status == .forbidden
            || status == .unauthorized
            || status.code == 995
    }

    private func ensureMenuItem(app: Application, adminToken: String) async throws -> MenuItem {
        let listed = try await request(app, .GET, "/api/auth/menu?limit=1", token: adminToken)
        if listed.status == .ok {
            let page = try decodeBody(PaginatedMenuItems.self, from: listed)
            if let first = page.items.first { return first }
        }
        let created = try await request(
            app, .POST, "/api/auth/menu",
            token: adminToken,
            body: CreateMenuItemRequest(
                name: "Latte",
                priceCents: 450,
                isAvailable: true,
                sizeOptions: [MenuSizeOption(name: "Large", priceDeltaCents: 75)]))
        #expect(created.status == .ok || created.status == .created)
        return try decodeBody(MenuItem.self, from: created)
    }

    private func placeOrder(
        app: Application,
        token: String,
        customerName: String,
        notes: String? = nil,
        adminToken: String
    ) async throws -> Order {
        let menu = try await ensureMenuItem(app: app, adminToken: adminToken)
        let body = CreateOrderRequest(
            customerName: customerName,
            items: [OrderItem(menuItemId: menu.id, name: menu.name, quantity: 1, notes: notes)],
            pickupTime: nil,
            channel: .pickup,
            serviceType: .barista)
        let res = try await request(app, .POST, "/api/auth/orders", token: token, body: body)
        #expect(res.status == .ok || res.status == .created)
        return try decodeBody(Order.self, from: res)
    }

    // MARK: - BinaryCodable wire names

    @Test func binaryWireNamesMatchClientContracts() throws {
        // Encode/decode round-trips prove the concrete type names clients send.
        let menuCreate = CreateMenuItemRequest(
            name: "Cappuccino",
            description: "Foam",
            priceCents: 450,
            isAvailable: true,
            category: "Coffee",
            sizeOptions: [MenuSizeOption(name: "Large", priceDeltaCents: 100)],
            prepSeconds: 180,
            prepStation: "Barista",
            allergens: [.milk])
        let menuData = try BinaryEncoder().encode(menuCreate)
        let menuDecoded = try BinaryDecoder().decode(CreateMenuItemRequest.self, from: menuData)
        #expect(menuDecoded.name == "Cappuccino")
        #expect(menuDecoded.sizeOptions?.first?.name == "Large")
        #expect(menuDecoded.allergens == [.milk])

        let menuUpdate = UpdateMenuItemRequest(priceCents: 475, isAvailable: false)
        let updateDecoded = try BinaryDecoder().decode(
            UpdateMenuItemRequest.self,
            from: try BinaryEncoder().encode(menuUpdate))
        #expect(updateDecoded.priceCents == 475)
        #expect(updateDecoded.isAvailable == false)

        let orderCreate = CreateOrderRequest(
            customerName: "Pat",
            items: [OrderItem(menuItemId: "m1", name: "Espresso", quantity: 2, notes: "Size: Large (+$1.00)")],
            channel: .pickup)
        let orderDecoded = try BinaryDecoder().decode(
            CreateOrderRequest.self,
            from: try BinaryEncoder().encode(orderCreate))
        #expect(orderDecoded.items.first?.notes?.contains("Size: Large") == true)

        let status = UpdateOrderStatusRequest(status: .canceled)
        let statusDecoded = try BinaryDecoder().decode(
            UpdateOrderStatusRequest.self,
            from: try BinaryEncoder().encode(status))
        #expect(statusDecoded.status == .canceled)

        let reservation = CreateReservationRequest(
            name: "Alex", partySize: 3, startTime: Date(), status: .active)
        let resDecoded = try BinaryDecoder().decode(
            CreateReservationRequest.self,
            from: try BinaryEncoder().encode(reservation))
        #expect(resDecoded.partySize == 3)
        #expect(resDecoded.status == .active)
    }

    // MARK: - Menu CMS

    @Test func menuCMSPersistsExtendedFields() async throws {
        let adminEmail = "cms-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail)

            let create = CreateMenuItemRequest(
                name: "Flat White",
                description: "Velvety",
                priceCents: 425,
                isAvailable: true,
                category: "Coffee",
                sizeOptions: [
                    MenuSizeOption(name: "Small", priceDeltaCents: 0),
                    MenuSizeOption(name: "Large", priceDeltaCents: 75),
                ],
                prepSeconds: 150,
                prepStation: "Barista",
                allergens: [.milk, .soy])
            var res = try await request(app, .POST, "/api/auth/menu", token: adminToken, body: create)
            #expect(res.status == .ok || res.status == .created)
            let created = try decodeBody(MenuItem.self, from: res)
            #expect(created.name == "Flat White")
            #expect(created.description == "Velvety")
            #expect(created.category == "Coffee")
            #expect(created.sizeOptions?.count == 2)
            #expect(created.prepSeconds == 150)
            #expect(created.prepStation == "Barista")
            #expect(created.allergens?.contains(.milk) == true)

            let update = UpdateMenuItemRequest(
                name: "Flat White+",
                priceCents: 450,
                isAvailable: false,
                sizeOptions: [MenuSizeOption(name: "Regular", priceDeltaCents: 0)],
                prepSeconds: 120,
                allergens: [.milk])
            res = try await request(app, .PUT, "/api/auth/menu/\(created.id)", token: adminToken, body: update)
            #expect(res.status == .ok)
            let updated = try decodeBody(MenuItem.self, from: res)
            #expect(updated.name == "Flat White+")
            #expect(updated.priceCents == 450)
            #expect(updated.isAvailable == false)
            #expect(updated.sizeOptions?.count == 1)
            #expect(updated.prepSeconds == 120)
            #expect(updated.allergens == [.milk])

            res = try await request(app, .DELETE, "/api/auth/menu/\(created.id)", token: adminToken)
            #expect(res.status == .noContent)
            // Soft-delete: item remains fetchable by id with deletedAt set; hidden from default list.
            res = try await request(app, .GET, "/api/auth/menu/\(created.id)", token: adminToken)
            #expect(res.status == .ok)
            let archived = try decodeBody(MenuItem.self, from: res)
            #expect(archived.deletedAt != nil)
            res = try await request(app, .GET, "/api/auth/menu", token: adminToken)
            let listed = try decodeBody(PaginatedMenuItems.self, from: res).items
            #expect(!listed.contains(where: { $0.id == created.id }))
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func menuCreateRequiresAdmin() async throws {
        let adminEmail = "cms-gate@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await registerAndLogin(app: app, email: "cms-user@example.com")

            let create = CreateMenuItemRequest(
                name: "Nope", priceCents: 100, isAvailable: true)
            let res = try await request(app, .POST, "/api/auth/menu", token: userToken, body: create)
            #expect(isAdminDenied(res.status))
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    // MARK: - Orders ownership / board rules

    @Test func orderStampsCustomerUserIdAndScopesLists() async throws {
        let adminEmail = "orders-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {

            let (alice, aliceToken) = try await registerAndLogin(app: app, email: "alice@example.com", name: "Alice")
            let (bob, bobToken) = try await registerAndLogin(app: app, email: "bob@example.com", name: "Bob")
            let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail)

            let aliceOrder = try await placeOrder(
                app: app, token: aliceToken, customerName: "Alice", adminToken: adminToken)
            #expect(aliceOrder.customerUserId == alice.id)
            #expect(aliceOrder.channel == .pickup)

            let bobOrder = try await placeOrder(
                app: app, token: bobToken, customerName: "Bob", adminToken: adminToken)
            #expect(bobOrder.customerUserId == bob.id)

            var res = try await request(app, .GET, "/api/auth/orders", token: aliceToken)
            #expect(res.status == .ok)
            let aliceList = try decodeBody(PaginatedOrders.self, from: res).items
            #expect(aliceList.count == 1)
            #expect(aliceList.first?.id == aliceOrder.id)

            res = try await request(app, .GET, "/api/auth/orders", token: bobToken)
            let bobList = try decodeBody(PaginatedOrders.self, from: res).items
            #expect(bobList.count == 1)
            #expect(bobList.first?.id == bobOrder.id)

            res = try await request(app, .GET, "/api/auth/orders", token: adminToken)
            let adminList = try decodeBody(PaginatedOrders.self, from: res).items
            #expect(adminList.count >= 2)
            #expect(adminList.contains(where: { $0.id == aliceOrder.id }))
            #expect(adminList.contains(where: { $0.id == bobOrder.id }))

            // Alice cannot fetch Bob's order
            res = try await request(app, .GET, "/api/auth/orders/\(bobOrder.id)", token: aliceToken)
            #expect(res.status == .forbidden)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func customerCanCancelOwnPendingOnly() async throws {
        let adminEmail = "cancel-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {

            let (_, aliceToken) = try await registerAndLogin(app: app, email: "cancel-alice@example.com")
            let (_, bobToken) = try await registerAndLogin(app: app, email: "cancel-bob@example.com")
            let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail)

            let pending = try await placeOrder(
                app: app, token: aliceToken, customerName: "Alice",
                notes: "Size: Large (+$0.75)", adminToken: adminToken)
            #expect(pending.status == .pending)
            #expect(pending.items.first?.notes?.contains("Size: Large") == true)

            // Customer cannot advance to preparing
            var res = try await request(
                app, .PUT, "/api/auth/orders/\(pending.id)/status",
                token: aliceToken,
                body: UpdateOrderStatusRequest(status: .preparing))
            #expect(res.status == .forbidden)

            // Bob cannot cancel Alice's order
            res = try await request(
                app, .PUT, "/api/auth/orders/\(pending.id)/status",
                token: bobToken,
                body: UpdateOrderStatusRequest(status: .canceled))
            #expect(res.status == .forbidden)

            // Alice can cancel own pending
            res = try await request(
                app, .PUT, "/api/auth/orders/\(pending.id)/status",
                token: aliceToken,
                body: UpdateOrderStatusRequest(status: .canceled))
            #expect(res.status == .ok)
            let canceled = try decodeBody(Order.self, from: res)
            #expect(canceled.status == .canceled)

            // Admin can advance a fresh order through the board
            let boardOrder = try await placeOrder(
                app: app, token: aliceToken, customerName: "Alice", adminToken: adminToken)
            for next in [OrderStatus.preparing, .ready, .completed] {
                res = try await request(
                    app, .PUT, "/api/auth/orders/\(boardOrder.id)/status",
                    token: adminToken,
                    body: UpdateOrderStatusRequest(status: next))
                #expect(res.status == .ok)
                let updated = try decodeBody(Order.self, from: res)
                #expect(updated.status == next)
            }

            // Customer cannot cancel after it left pending (place + admin prepare)
            let preparing = try await placeOrder(
                app: app, token: aliceToken, customerName: "Alice", adminToken: adminToken)
            res = try await request(
                app, .PUT, "/api/auth/orders/\(preparing.id)/status",
                token: adminToken,
                body: UpdateOrderStatusRequest(status: .preparing))
            #expect(res.status == .ok)
            res = try await request(
                app, .PUT, "/api/auth/orders/\(preparing.id)/status",
                token: aliceToken,
                body: UpdateOrderStatusRequest(status: .canceled))
            #expect(res.status == .forbidden)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func emptyOrderRejected() async throws {
        let adminEmail = "empty-order-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {
            let (_, token) = try await registerAndLogin(app: app, email: "empty-order@example.com")

            let body = CreateOrderRequest(customerName: "Pat", items: [])
            let res = try await request(app, .POST, "/api/auth/orders", token: token, body: body)
            #expect(res.status == .badRequest)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    // MARK: - Reservations

    @Test func reservationCreatePersistsOptionalFields() async throws {
        let adminEmail = "res-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {
            let (_, token) = try await registerAndLogin(app: app, email: "res-user@example.com", name: "Riley")

            let start = Date().addingTimeInterval(7200)
            let body = CreateReservationRequest(
                name: "Riley",
                partySize: 4,
                startTime: start,
                phone: "+1-555-0100",
                notes: "Window",
                durationMinutes: 90,
                status: .active,
                specialOccasion: "Birthday")
            let res = try await request(app, .POST, "/api/auth/reservations", token: token, body: body)
            #expect(res.status == .ok || res.status == .created)
            let created = try decodeBody(Reservation.self, from: res)
            #expect(created.name == "Riley")
            #expect(created.partySize == 4)
            #expect(created.phone == "+1-555-0100")
            #expect(created.notes == "Window")
            #expect(created.durationMinutes == 90)
            #expect(created.specialOccasion == "Birthday")
            #expect(created.status == .active)
            #expect(created.customerUserId != nil)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func reservationScopedAndCancelableByOwner() async throws {
        let adminEmail = "res-scope-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {

            let (alice, aliceToken) = try await registerAndLogin(app: app, email: "res-alice@example.com", name: "Alice")
            let (_, bobToken) = try await registerAndLogin(app: app, email: "res-bob@example.com", name: "Bob")
            let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail)

            let body = CreateReservationRequest(
                name: "Alice",
                partySize: 2,
                startTime: Date().addingTimeInterval(3600),
                status: .active)
            var res = try await request(app, .POST, "/api/auth/reservations", token: aliceToken, body: body)
            #expect(res.status == .ok || res.status == .created)
            let created = try decodeBody(Reservation.self, from: res)
            #expect(created.customerUserId == alice.id)

            res = try await request(app, .GET, "/api/auth/reservations", token: bobToken)
            let bobList = try decodeBody(PaginatedReservations.self, from: res).items
            #expect(!bobList.contains(where: { $0.id == created.id }))

            res = try await request(app, .GET, "/api/auth/reservations", token: aliceToken)
            let aliceList = try decodeBody(PaginatedReservations.self, from: res).items
            #expect(aliceList.contains(where: { $0.id == created.id }))

            res = try await request(app, .GET, "/api/auth/reservations", token: adminToken)
            let adminList = try decodeBody(PaginatedReservations.self, from: res).items
            #expect(adminList.contains(where: { $0.id == created.id }))

            res = try await request(
                app, .PUT, "/api/auth/reservations/\(created.id)/cancel",
                token: bobToken)
            #expect(res.status == .forbidden)

            res = try await request(
                app, .PUT, "/api/auth/reservations/\(created.id)/cancel",
                token: aliceToken)
            #expect(res.status == .ok)
            let canceled = try decodeBody(Reservation.self, from: res)
            #expect(canceled.status == .canceled)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    // MARK: - Profile

    @Test func authenticatedUserCanUpdateProfile() async throws {
        let adminEmail = "profile-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {

            let (_, token) = try await registerAndLogin(
                app: app, email: "profile-user@example.com", name: "Before")

            let update = UpdateProfileRequest(name: "After Name", email: "profile-user-renamed@example.com")
            var res = try await request(app, .PUT, "/api/auth/profile", token: token, body: update)
            #expect(res.status == .ok)
            let updated = try decodeBody(UserPublic.self, from: res)
            #expect(updated.name == "After Name")
            #expect(updated.email == "profile-user-renamed@example.com")

            // Conflict when email already taken
            _ = try await registerAndLogin(app: app, email: "taken@example.com")
            res = try await request(
                app, .PUT, "/api/auth/profile",
                token: token,
                body: UpdateProfileRequest(name: nil, email: "taken@example.com"))
            #expect(res.status == .conflict)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    // MARK: - Loyalty

    @Test func loyaltyGetByUserId() async throws {
        let adminEmail = "loyalty-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {
            let (user, adminToken) = try await registerAndLogin(app: app, email: adminEmail)

            struct Enroll: Content { let userId: String }
            var res = try await request(
                app, .POST, "/api/auth/loyalty/enroll",
                token: adminToken,
                body: Enroll(userId: user.id))
            #expect(res.status == .ok)

            // Lookup by userId (client Profile path), not only loyalty ObjectId
            res = try await request(app, .GET, "/api/auth/loyalty/\(user.id)", token: adminToken)
            #expect(res.status == .ok)
            let byUser = try decodeBody(LoyaltyAccountPublic.self, from: res)
            #expect(byUser.userId == user.id)
            #expect(byUser.points == 0)

            res = try await request(app, .GET, "/api/auth/loyalty/\(byUser.id)", token: adminToken)
            #expect(res.status == .ok)
            let byId = try decodeBody(LoyaltyAccountPublic.self, from: res)
            #expect(byId.id == byUser.id)

            res = try await request(
                app, .GET, "/api/auth/loyalty/missing-user-id", token: adminToken)
            #expect(res.status == .notFound)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    // MARK: - DEBUG seed

    @Test func debugSeedLoadsDemoDataIdempotently() async throws {
        #if !DEBUG
        // Route is compiled out of Release binaries.
        return
        #else
        let adminEmail = "seed-admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail)
            let (_, userToken) = try await registerAndLogin(app: app, email: "seed-user@example.com")

            // Non-admin forbidden
            var res = try await request(app, .POST, "/api/auth/debug/seed", token: userToken)
            #expect(isAdminDenied(res.status))

            // First seed should load demo data
            res = try await request(app, .POST, "/api/auth/debug/seed", token: adminToken)
            #expect(res.status == .ok)
            let first = try decodeBody(DebugSeedController.SeedResult.self, from: res)
            #expect(first.seeded == true)

            res = try await request(app, .GET, "/api/auth/menu", token: adminToken)
            let menu = try decodeBody(PaginatedMenuItems.self, from: res).items
            #expect(menu.count >= 1)

            res = try await request(app, .GET, "/api/auth/inventory", token: adminToken)
            let inventory = try decodeBody(PaginatedInventoryItems.self, from: res).items
            #expect(inventory.count >= 1)

            // Second call is idempotent (inventory already present)
            res = try await request(app, .POST, "/api/auth/debug/seed", token: adminToken)
            #expect(res.status == .ok)
            let second = try decodeBody(DebugSeedController.SeedResult.self, from: res)
            #expect(second.seeded == false)

            // Reseed wipes and reloads
            res = try await request(app, .POST, "/api/auth/debug/reseed", token: adminToken)
            #expect(res.status == .ok)
            let reseeded = try decodeBody(DebugSeedController.SeedResult.self, from: res)
            #expect(reseeded.seeded == true)

            res = try await request(app, .GET, "/api/auth/menu", token: adminToken)
            let menuAfter = try decodeBody(PaginatedMenuItems.self, from: res).items
            #expect(menuAfter.count >= 8)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
        #endif
    }

    @Test func debugSeedUnitHelperSkipsWhenInventoryPresent() async throws {
        let store = TestableMongoStore(seedDummyData: false)
        let logger = Logger(label: "seed-test")

        try await DevDataSeed.ensureMongoSeeded(store: store, logger: logger)
        let afterFirst = try await store.listInventory().count
        #expect(afterFirst > 0)
        let menuCount = try await store.listMenu().count
        #expect(menuCount > 0)

        try await DevDataSeed.ensureMongoSeeded(store: store, logger: logger)
        let afterSecond = try await store.listInventory().count
        #expect(afterSecond == afterFirst)
    }

    @Test func reseedReplacesCatalogWithRealisticCafe() async throws {
        let store = TestableMongoStore(seedDummyData: false)
        let logger = Logger(label: "reseed-test")
        try await DevDataSeed.ensureMongoSeeded(store: store, logger: logger)

        try await DevDataSeed.reseedMongo(store: store, logger: logger)
        let inventory = try await store.listInventory()
        let menu = try await store.listMenu()
        let tables = try await store.listTables()
        let recipes = try await store.listRecipes()
        let paid = try await store.listOrders().filter {
            $0.status == .completed && $0.paymentStatus == .paid
        }

        #expect(inventory.count >= 10)
        #expect(menu.count >= 10)
        #expect(tables.count >= 12)
        #expect(recipes.count == menu.count)
        let beans = inventory.first(where: { $0.sku == "BEANS-ESP-1KG" })
        let milk = inventory.first(where: { $0.sku == "DAIRY-MILK-1L" })
        #expect(beans?.unit == "g")
        #expect(milk?.unit == "l")
        #expect(paid.count > 100)
        #expect(menu.contains(where: { $0.name == "Cafe Latte" }))
    }

    @Test func seedHistoricalOrdersArePaidWithMoneyFields() throws {
        let bundle = DemoCafeSeed.makeBundle()
        let completed = bundle.orders.filter { $0.status == .completed }
        #expect(!completed.isEmpty)
        for order in completed {
            #expect(order.paymentStatus == .paid)
            #expect((order.subtotalCents ?? 0) > 0)
            #expect(order.totalCents == order.subtotalCents)
            #expect(order.items.allSatisfy { ($0.unitPriceCents ?? 0) > 0 })
        }
        let menuIds = Set(bundle.menu.map(\.id))
        #expect(completed.allSatisfy { $0.items.allSatisfy { menuIds.contains($0.menuItemId) } })
    }
}

//
//  EnterpriseHardeningTests.swift
//  ApiTests
//
//  TDD for production hardenings: refresh rotation, size pricing,
//  team seed gate, auth rate limit, stock atomicity policy.
//

@preconcurrency import BSON
import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct EnterpriseHardeningTests {

    // MARK: - Realtime policy

    @Test func realtimeDoesNotRelayPeerFrames() {
        #expect(RealtimePolicy.relayAuthenticatedPeerFrames == false)
    }

    // MARK: - Refresh rotation + password revoke

    @Test func refreshRotatesTokenAndInvalidatesOld() async throws {
        try await APITestHelpers.withApp(adminEmail: "harden-refresh-admin@example.com") { app in
            struct LoginRequest: Content { let email: String; let password: String }

            _ = try await APITestHelpers.registerAndLogin(
                app: app, email: "harden-refresh@example.com")
            let loginRes = try await APITestHelpers.request(
                app, .POST, "/api/login",
                body: LoginRequest(email: "harden-refresh@example.com", password: "password123"))
            #expect(loginRes.status == .ok)
            let login = try APITestHelpers.decodeBody(TokenResponse.self, from: loginRes)
            let oldRefresh = try #require(login.refreshToken)

            var refreshReq = try await APITestHelpers.request(
                app, .POST, "/api/auth/refresh", token: oldRefresh)
            #expect(refreshReq.status == .ok)
            let rotated = try APITestHelpers.decodeBody(TokenResponse.self, from: refreshReq)
            let newRefresh = try #require(rotated.refreshToken)
            #expect(newRefresh != oldRefresh)
            #expect(!rotated.token.isEmpty)

            refreshReq = try await APITestHelpers.request(
                app, .POST, "/api/auth/refresh", token: oldRefresh)
            #expect(refreshReq.status == .unauthorized)
        }
    }

    @Test func passwordChangeRevokesRefreshTokens() async throws {
        try await APITestHelpers.withApp(adminEmail: "harden-pw-admin@example.com") { app in
            struct LoginRequest: Content { let email: String; let password: String }
            struct UpdatePassword: Content {
                let oldPassword: String
                let newPassword: String
            }

            let (_, access) = try await APITestHelpers.registerAndLogin(
                app: app, email: "harden-pw@example.com")
            let loginRes = try await APITestHelpers.request(
                app, .POST, "/api/login",
                body: LoginRequest(email: "harden-pw@example.com", password: "password123"))
            let login = try APITestHelpers.decodeBody(TokenResponse.self, from: loginRes)
            let refresh = try #require(login.refreshToken)

            let pwRes = try await APITestHelpers.request(
                app, .PUT, "/api/auth/update-password",
                token: access,
                body: UpdatePassword(oldPassword: "password123", newPassword: "password456"))
            #expect(pwRes.status == .ok)

            let refreshRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/refresh", token: refresh)
            #expect(refreshRes.status == .unauthorized)
        }
    }

    // MARK: - Size pricing

    @Test func sizeNameControlsPriceNotesDoNot() async throws {
        try await APITestHelpers.withApp(adminEmail: "harden-size-admin@example.com") { app in
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "harden-size-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "harden-size-admin@example.com")
            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Sized Latte",
                    priceCents: 400,
                    isAvailable: true,
                    sizeOptions: [
                        .init(name: "Small", priceDeltaCents: 0),
                        .init(name: "Large", priceDeltaCents: 100),
                    ]))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

            var body = CreateOrderRequest(
                customerName: "Guest",
                items: [
                    OrderItem(
                        menuItemId: menu.id,
                        quantity: 1,
                        notes: "Size: Small",
                        unitPriceCents: 1,
                        sizeName: "Large")
                ],
                channel: .pickup)
            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .ok || res.status == .created)
            var order = try APITestHelpers.decodeBody(Order.self, from: res)
            #expect(order.subtotalCents == 500)
            #expect(order.items.first?.unitPriceCents == 500)

            body = CreateOrderRequest(
                customerName: "Guest",
                items: [
                    OrderItem(
                        menuItemId: menu.id,
                        quantity: 1,
                        notes: "Size: Large (+$1.00)",
                        unitPriceCents: 1)
                ],
                channel: .pickup)
            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .ok || res.status == .created)
            order = try APITestHelpers.decodeBody(Order.self, from: res)
            #expect(order.subtotalCents == 400)

            body = CreateOrderRequest(
                customerName: "Guest",
                items: [
                    OrderItem(menuItemId: menu.id, quantity: 1, sizeName: "Huge")
                ],
                channel: .pickup)
            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .badRequest)
        }
    }

    // MARK: - Team seed

    @Test func teamSeedDisabledWhenSeedFlagFalse() {
        #expect(TeamController.shouldSeedDemoRosterForTests() == false)
    }

    // MARK: - Auth rate limit

    @Test func loginRateLimitedAfterBurst() async throws {
        try await APITestHelpers.withApp(adminEmail: "harden-rl-admin@example.com") { app in
            struct LoginRequest: Content { let email: String; let password: String }
            _ = try await APITestHelpers.registerAndLogin(
                app: app, email: "harden-rl@example.com")
            await AuthRateLimiter.shared.reset()

            var sawLimited = false
            for _ in 0..<25 {
                let res = try await APITestHelpers.request(
                    app, .POST, "/api/login",
                    body: LoginRequest(email: "harden-rl@example.com", password: "wrong-password"))
                if res.status == .tooManyRequests {
                    sawLimited = true
                    break
                }
            }
            #expect(sawLimited)
        }
    }

    // MARK: - Stock deduct via store (actor-atomic)

    @Test func storeDeductInventoryIsAtomicWithinActor() async throws {
        let store = TestableMongoStore(seedDummyData: false)
        let id = ObjectId().hexString
        _ = try await store.create(
            inventoryItem: InventoryItem(
                id: id, sku: "ATOM-1", name: "Beans", quantity: 5,
                reorderThreshold: 1, unit: "bag"))
        try await store.deductInventory(bySKU: ["ATOM-1": 3])
        #expect(try await store.findInventory(by: id)?.quantity == 2)
        do {
            try await store.deductInventory(bySKU: ["ATOM-1": 10])
            Issue.record("Expected insufficient stock error")
        } catch {
            // expected
        }
        #expect(try await store.findInventory(by: id)?.quantity == 2)
    }
}

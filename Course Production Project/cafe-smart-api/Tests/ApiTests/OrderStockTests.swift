//
//  OrderStockTests.swift
//  ApiTests
//

@preconcurrency import BSON
import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct OrderStockTests {

    private func seedStockedMenu(
        app: Application,
        adminToken: String,
        qty: Int
    ) async throws -> (menu: MenuItem, inventoryId: String) {
        let invRes = try await APITestHelpers.request(
            app, .POST, "/api/auth/inventory",
            token: adminToken,
            body: CreateInventoryItemRequest(
                sku: "STOCK-MILK-\(ObjectId().hexString.prefix(6))",
                name: "Stock Milk",
                quantity: qty,
                reorderThreshold: 1,
                unit: "L"))
        #expect(invRes.status == .ok || invRes.status == .created)
        let inv = try APITestHelpers.decodeBody(InventoryItem.self, from: invRes)

        let menuRes = try await APITestHelpers.request(
            app, .POST, "/api/auth/menu",
            token: adminToken,
            body: CreateMenuItemRequest(
                name: "Stock Latte", priceCents: 400, isAvailable: true))
        #expect(menuRes.status == .ok || menuRes.status == .created)
        let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

        let recipeRes = try await APITestHelpers.request(
            app, .POST, "/api/auth/recipes",
            token: adminToken,
            body: CreateRecipeRequest(
                menuItemId: menu.id,
                components: [.init(sku: inv.sku, unitsPerItem: 1.0)]))
        #expect(recipeRes.status == .ok || recipeRes.status == .created)
        return (menu, inv.id)
    }

    @Test func deductsStockOnCreateAndRestoresOnPendingCancel() async throws {
        let adminEmail = "stock-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "stock-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let seeded = try await seedStockedMenu(app: app, adminToken: adminToken, qty: 5)

            let body = CreateOrderRequest(
                customerName: "Guest",
                items: [OrderItem(menuItemId: seeded.menu.id, quantity: 2)],
                channel: .pickup)
            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .ok || res.status == .created)
            let order = try APITestHelpers.decodeBody(Order.self, from: res)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory/\(seeded.inventoryId)", token: adminToken)
            #expect(res.status == .ok)
            let afterCreate = try APITestHelpers.decodeBody(InventoryItem.self, from: res)
            #expect(afterCreate.quantity == 3)

            res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(order.id)/status",
                token: userToken,
                body: UpdateOrderStatusRequest(status: .canceled))
            #expect(res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory/\(seeded.inventoryId)", token: adminToken)
            let afterCancel = try APITestHelpers.decodeBody(InventoryItem.self, from: res)
            #expect(afterCancel.quantity == 5)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func rejectsInsufficientStock() async throws {
        let adminEmail = "stock-low-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "stock-low-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let seeded = try await seedStockedMenu(app: app, adminToken: adminToken, qty: 1)

            let body = CreateOrderRequest(
                customerName: "Guest",
                items: [OrderItem(menuItemId: seeded.menu.id, quantity: 3)],
                channel: .pickup)
            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .conflict || res.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func rejectsIllegalKitchenJump() async throws {
        let adminEmail = "fsm-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "fsm-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "FSM Latte", priceCents: 300, isAvailable: true))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)
            let created = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            let order = try APITestHelpers.decodeBody(Order.self, from: created)

            let jump = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(order.id)/status",
                token: adminToken,
                body: UpdateOrderStatusRequest(status: .ready))
            #expect(jump.status == .conflict || jump.status == .badRequest)

            let regress = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(order.id)/status",
                token: adminToken,
                body: UpdateOrderStatusRequest(status: .preparing))
            #expect(regress.status == .ok)
            let back = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(order.id)/status",
                token: adminToken,
                body: UpdateOrderStatusRequest(status: .pending))
            #expect(back.status == .conflict || back.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

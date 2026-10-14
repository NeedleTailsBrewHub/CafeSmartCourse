//
//  OrderKitchenTests.swift
//  ApiTests
//
//  Kitchen board status pipeline + list filters (TDD for stage advances).
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct OrderKitchenTests {

    private func seedMenu(app: Application, adminToken: String) async throws -> MenuItem {
        let res = try await APITestHelpers.request(
            app, .POST, "/api/auth/menu",
            token: adminToken,
            body: CreateMenuItemRequest(
                name: "Kitchen Latte",
                priceCents: 450,
                isAvailable: true))
        #expect(res.status == .ok || res.status == .created)
        return try APITestHelpers.decodeBody(MenuItem.self, from: res)
    }

    private func placeOrder(
        app: Application,
        token: String,
        menuId: String,
        customerName: String
    ) async throws -> Order {
        let body = CreateOrderRequest(
            customerName: customerName,
            items: [OrderItem(menuItemId: menuId, name: "Kitchen Latte", quantity: 1)],
            pickupTime: nil,
            channel: .pickup,
            serviceType: .barista)
        let res = try await APITestHelpers.request(
            app, .POST, "/api/auth/orders", token: token, body: body)
        #expect(res.status == .ok || res.status == .created)
        return try APITestHelpers.decodeBody(Order.self, from: res)
    }

    @Test func kitchenStatusPipelineAdvancesAndLeavesOpenList() async throws {
        let adminEmail = "kitchen-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "kitchen-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let created = try await placeOrder(
                app: app, token: userToken, menuId: menu.id, customerName: "Kitchen Guest")
            #expect(created.status == .pending)

            let stages: [OrderStatus] = [.preparing, .ready, .completed]
            var current = created
            for stage in stages {
                let res = try await APITestHelpers.request(
                    app, .PUT, "/api/auth/orders/\(current.id)/status",
                    token: adminToken,
                    body: UpdateOrderStatusRequest(status: stage))
                #expect(res.status == .ok)
                current = try APITestHelpers.decodeBody(Order.self, from: res)
                #expect(current.status == stage)
            }

            // Open kitchen query must not still return the completed ticket.
            var res = try await APITestHelpers.request(
                app, .GET,
                "/api/auth/orders?statuses=pending,preparing,ready&limit=80",
                token: adminToken)
            #expect(res.status == .ok)
            let open = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(!open.items.contains(where: { $0.id == created.id }))

            // Terminal query should include it.
            res = try await APITestHelpers.request(
                app, .GET,
                "/api/auth/orders?statuses=completed,canceled&limit=24",
                token: adminToken)
            #expect(res.status == .ok)
            let done = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(done.items.contains(where: { $0.id == created.id && $0.status == .completed }))
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func bulkAdvanceAllOrdersInSameStage() async throws {
        let adminEmail = "kitchen-bulk@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "kitchen-bulk-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let a = try await placeOrder(
                app: app, token: userToken, menuId: menu.id, customerName: "A")
            let b = try await placeOrder(
                app: app, token: userToken, menuId: menu.id, customerName: "B")
            #expect(a.status == .pending)
            #expect(b.status == .pending)

            for id in [a.id, b.id] {
                let res = try await APITestHelpers.request(
                    app, .PUT, "/api/auth/orders/\(id)/status",
                    token: adminToken,
                    body: UpdateOrderStatusRequest(status: .preparing))
                #expect(res.status == .ok)
            }

            var res = try await APITestHelpers.request(
                app, .GET, "/api/auth/orders?statuses=pending&limit=80",
                token: adminToken)
            let pending = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(!pending.items.contains(where: { $0.id == a.id || $0.id == b.id }))

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/orders?statuses=preparing&limit=80",
                token: adminToken)
            let preparing = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(preparing.items.filter { $0.id == a.id || $0.id == b.id }.count == 2)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func updateStatusPersistsAcrossReload() async throws {
        let adminEmail = "kitchen-persist@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "kitchen-persist-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(app: app, adminToken: adminToken)
            let created = try await placeOrder(
                app: app, token: userToken, menuId: menu.id, customerName: "Persist Me")

            var res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(created.id)/status",
                token: adminToken,
                body: UpdateOrderStatusRequest(status: .preparing))
            #expect(res.status == .ok)
            res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(created.id)/status",
                token: adminToken,
                body: UpdateOrderStatusRequest(status: .ready))
            #expect(res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/orders/\(created.id)",
                token: adminToken)
            #expect(res.status == .ok)
            let reloaded = try APITestHelpers.decodeBody(Order.self, from: res)
            #expect(reloaded.status == .ready)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func guestCanCancelPendingOnly() async throws {
        let adminEmail = "kitchen-cancel-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "kitchen-cancel-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let order = try await placeOrder(
                app: app, token: userToken, menuId: menu.id, customerName: "Cancel Me")

            var res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(order.id)/status",
                token: userToken,
                body: UpdateOrderStatusRequest(status: .canceled))
            #expect(res.status == .ok)
            let canceled = try APITestHelpers.decodeBody(Order.self, from: res)
            #expect(canceled.status == .canceled)

            let other = try await placeOrder(
                app: app, token: userToken, menuId: menu.id, customerName: "Started")
            res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(other.id)/status",
                token: adminToken,
                body: UpdateOrderStatusRequest(status: .preparing))
            #expect(res.status == .ok)

            res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/orders/\(other.id)/status",
                token: userToken,
                body: UpdateOrderStatusRequest(status: .canceled))
            #expect(
                res.status == .forbidden
                    || res.status == .unauthorized
                    || res.status == .badRequest
                    || res.status.code == 995
            )
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

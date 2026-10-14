//
//  OrderPricingTests.swift
//  ApiTests
//
//  Server-authoritative pricing: ignore client unitPriceCents; reject unavailable.
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct OrderPricingTests {

    private func seedMenu(
        app: Application,
        adminToken: String,
        priceCents: Int = 500,
        isAvailable: Bool = true,
        sizeOptions: [MenuSizeOption]? = nil
    ) async throws -> MenuItem {
        let res = try await APITestHelpers.request(
            app, .POST, "/api/auth/menu",
            token: adminToken,
            body: CreateMenuItemRequest(
                name: "Priced Latte",
                priceCents: priceCents,
                isAvailable: isAvailable,
                sizeOptions: sizeOptions))
        #expect(res.status == .ok || res.status == .created)
        return try APITestHelpers.decodeBody(MenuItem.self, from: res)
    }

    @Test func ignoresClientUnderpricedUnitPriceCents() async throws {
        let adminEmail = "pricing-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pricing-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 500)

            let body = CreateOrderRequest(
                customerName: "Cheapskate",
                items: [
                    OrderItem(
                        menuItemId: menu.id,
                        name: "Priced Latte",
                        quantity: 2,
                        unitPriceCents: 1)
                ],
                channel: .pickup,
                serviceType: .barista)
            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .ok || res.status == .created)
            let order = try APITestHelpers.decodeBody(Order.self, from: res)
            #expect(order.subtotalCents == 1000)
            #expect(order.totalCents == 1000)
            #expect(order.items.allSatisfy { $0.unitPriceCents == 500 })
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func rejectsUnavailableMenuItem() async throws {
        let adminEmail = "pricing-unavail-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pricing-unavail-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(
                app: app, adminToken: adminToken, priceCents: 400, isAvailable: false)

            let body = CreateOrderRequest(
                customerName: "Guest",
                items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                channel: .pickup)
            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func appliesValidatedSizeDeltaFromSizeName() async throws {
        let adminEmail = "pricing-size-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pricing-size-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(
                app: app,
                adminToken: adminToken,
                priceCents: 400,
                sizeOptions: [
                    .init(name: "Small", priceDeltaCents: 0),
                    .init(name: "Large", priceDeltaCents: 100),
                ])

            let body = CreateOrderRequest(
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
            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: body)
            #expect(res.status == .ok || res.status == .created)
            let order = try APITestHelpers.decodeBody(Order.self, from: res)
            #expect(order.subtotalCents == 500)
            #expect(order.items.first?.unitPriceCents == 500)
            #expect(order.items.first?.sizeName == "Large")
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

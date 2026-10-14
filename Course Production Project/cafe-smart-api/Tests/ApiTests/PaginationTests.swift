//
//  PaginationTests.swift
//  ApiTests
//

import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct PaginationTests {
    @Test func ordersPaginationAndOwnership() async throws {
        let adminEmail = "page-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, aliceToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "page-alice@example.com", name: "Alice")
            let (_, bobToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "page-bob@example.com", name: "Bob")
            let (admin, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            #expect(admin.isAdmin == true)

            for i in 0..<5 {
                _ = try await APITestHelpers.placeOrder(
                    app: app, token: aliceToken, customerName: "Alice-\(i)",
                    adminToken: adminToken)
            }
            _ = try await APITestHelpers.placeOrder(
                app: app, token: bobToken, customerName: "Bob", adminToken: adminToken)

            var res = try await APITestHelpers.request(
                app, .GET, "/api/auth/orders?limit=2", token: aliceToken)
            #expect(res.status == .ok)
            let page1 = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(page1.items.count == 2)
            #expect(page1.page.hasMore == true)
            #expect(page1.page.nextCursor != nil)
            #expect(page1.items.allSatisfy { $0.customerName?.hasPrefix("Alice") == true })

            let cursor = page1.page.nextCursor!
            let encodedCursor =
                cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/orders?limit=2&cursor=\(encodedCursor)",
                token: aliceToken)
            #expect(res.status == .ok)
            let page2 = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(page2.items.count == 2)
            let ids = Set(page1.items.map(\.id)).union(page2.items.map(\.id))
            #expect(ids.count == 4)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/orders?q=Bob", token: bobToken)
            let bobPage = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(bobPage.items.count == 1)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/orders?limit=50", token: adminToken)
            #expect(res.status == .ok)
            let adminPage = try APITestHelpers.decodeBody(PaginatedOrders.self, from: res)
            #expect(adminPage.items.count >= 6)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func reservationsPaginationAndOwnership() async throws {
        let adminEmail = "page-res-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, aliceToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "page-res-alice@example.com", name: "Alice")
            let (_, bobToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "page-res-bob@example.com", name: "Bob")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            let start = Date().addingTimeInterval(3600)
            for i in 0..<3 {
                _ = try await APITestHelpers.request(
                    app, .POST, "/api/auth/reservations",
                    token: aliceToken,
                    body: CreateReservationRequest(
                        name: "Alice-\(i)", partySize: 2,
                        startTime: start.addingTimeInterval(Double(i) * 60),
                        phone: "555-010\(i)", notes: nil, durationMinutes: 60))
            }
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/reservations",
                token: bobToken,
                body: CreateReservationRequest(
                    name: "Bob Party", partySize: 4, startTime: start.addingTimeInterval(600),
                    phone: "555-9999", notes: "window", durationMinutes: 90))

            var res = try await APITestHelpers.request(
                app, .GET, "/api/auth/reservations?limit=2", token: aliceToken)
            #expect(res.status == .ok)
            let page1 = try APITestHelpers.decodeBody(PaginatedReservations.self, from: res)
            #expect(page1.items.count == 2)
            #expect(page1.page.hasMore == true)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/reservations?q=Bob", token: bobToken)
            let bobPage = try APITestHelpers.decodeBody(PaginatedReservations.self, from: res)
            #expect(bobPage.items.count == 1)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/reservations?limit=50", token: adminToken)
            let adminPage = try APITestHelpers.decodeBody(PaginatedReservations.self, from: res)
            #expect(adminPage.items.count >= 4)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func cursorRoundTrip() throws {
        let cursor = ListCursor(t: "123.456", id: "abc")
        let encoded = try cursor.encode()
        let decoded = try ListCursor.decode(encoded)
        #expect(decoded?.t == "123.456")
        #expect(decoded?.id == "abc")
    }
}

//
//  CmsOpsTests.swift
//  ApiTests
//

import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct CmsOpsTests {
    @Test func menuBulkAndAuditAndCSV() async throws {
        let adminEmail = "cms-menu@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(name: "Bulk A", priceCents: 100, isAvailable: true))
            let a = try APITestHelpers.decodeBody(MenuItem.self, from: res)
            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(name: "Bulk B", priceCents: 200, isAvailable: true))
            let b = try APITestHelpers.decodeBody(MenuItem.self, from: res)

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu/bulk",
                token: adminToken,
                body: MenuBulkRequest(ids: [a.id, b.id], action: "setAvailable", isAvailable: false))
            #expect(res.status == .ok)
            let bulk = try APITestHelpers.decodeBody(BulkResult.self, from: res)
            #expect(bulk.updated == 2)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/menu/export", token: adminToken)
            #expect(res.status == .ok)
            let csv = try APITestHelpers.decodeBody(CSVExportPayload.self, from: res)
            #expect(csv.csv.contains("Bulk A"))

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/audit?entityType=menu&entityId=\(a.id)&limit=10",
                token: adminToken)
            #expect(res.status == .ok)
            let audit = try APITestHelpers.decodeBody(PaginatedAuditEvents.self, from: res)
            #expect(audit.items.contains(where: { $0.action == "create" }))
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func inventoryBulkCreateArchiveSearch() async throws {
        let adminEmail = "cms-inv@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/inventory",
                token: adminToken,
                body: CreateInventoryItemRequest(
                    sku: "OAT-1", name: "Oat Milk", quantity: 5,
                    reorderThreshold: 10, unit: "L"))
            #expect(res.status == .ok || res.status == .created)
            let item = try APITestHelpers.decodeBody(InventoryItem.self, from: res)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory?q=Oat&lowStock=true", token: adminToken)
            #expect(res.status == .ok)
            let page = try APITestHelpers.decodeBody(PaginatedInventoryItems.self, from: res)
            #expect(page.items.contains(where: { $0.id == item.id }))

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/inventory/bulk",
                token: adminToken,
                body: InventoryBulkRequest(ids: [item.id], action: "softDelete"))
            #expect(res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory", token: adminToken)
            let hidden = try APITestHelpers.decodeBody(PaginatedInventoryItems.self, from: res)
            #expect(!hidden.items.contains(where: { $0.id == item.id }))

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory?includeDeleted=true", token: adminToken)
            let shown = try APITestHelpers.decodeBody(PaginatedInventoryItems.self, from: res)
            #expect(shown.items.contains(where: { $0.id == item.id }))
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

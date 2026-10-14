//
//  TaxonomyTests.swift
//  ApiTests
//

import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct TaxonomyTests {
    @Test func tagGroupAndTagCRUDWithUniqueness() async throws {
        let adminEmail = "tax-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (admin, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            #expect(admin.isAdmin == true)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/tag-groups",
                token: adminToken,
                body: CreateTagGroupRequest(name: "Allergens"))
            #expect(res.status == .ok || res.status == .created)
            let group = try APITestHelpers.decodeBody(TagGroup.self, from: res)
            #expect(group.name == "Allergens")

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/tag-groups",
                token: adminToken,
                body: CreateTagGroupRequest(name: "allergens"))
            #expect(res.status == .conflict)

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/tags",
                token: adminToken,
                body: CreateTagRequest(groupId: group.id, name: "Milk"))
            #expect(res.status == .ok || res.status == .created)
            // Qualify: Swift Testing also defines `Tag`.
            let tag = try APITestHelpers.decodeBody(cafe_smart_api.Tag.self, from: res)

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/tags",
                token: adminToken,
                body: CreateTagRequest(groupId: group.id, name: "milk"))
            #expect(res.status == .conflict)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/tag-groups/\(group.id)/tags?limit=10",
                token: adminToken)
            #expect(res.status == .ok)
            let page = try APITestHelpers.decodeBody(PaginatedTags.self, from: res)
            #expect(page.items.contains(where: { $0.id == tag.id }))

            res = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/tags/\(tag.id)",
                token: adminToken)
            #expect(res.status == .noContent)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func menuTagAttachAndFilter() async throws {
        let adminEmail = "tax-menu@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/tag-groups",
                token: adminToken,
                body: CreateTagGroupRequest(name: "Dietary"))
            let group = try APITestHelpers.decodeBody(TagGroup.self, from: res)
            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/tags",
                token: adminToken,
                body: CreateTagRequest(groupId: group.id, name: "Vegan"))
            let tag = try APITestHelpers.decodeBody(cafe_smart_api.Tag.self, from: res)

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Oat Latte", priceCents: 500, isAvailable: true, tagIds: [tag.id]))
            #expect(res.status == .ok || res.status == .created)
            let item = try APITestHelpers.decodeBody(MenuItem.self, from: res)
            #expect(item.tagIds == [tag.id])

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/menu?tagId=\(tag.id)",
                token: adminToken)
            #expect(res.status == .ok)
            let page = try APITestHelpers.decodeBody(PaginatedMenuItems.self, from: res)
            #expect(page.items.contains(where: { $0.id == item.id }))

            _ = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/tags/\(tag.id)", token: adminToken)
            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Fail Latte", priceCents: 400, isAvailable: true, tagIds: [tag.id]))
            #expect(res.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func softDeleteHidesMenuByDefault() async throws {
        let adminEmail = "tax-soft@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(name: "Temp", priceCents: 100, isAvailable: true))
            let item = try APITestHelpers.decodeBody(MenuItem.self, from: res)
            res = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/menu/\(item.id)", token: adminToken)
            #expect(res.status == .noContent)

            res = try await APITestHelpers.request(app, .GET, "/api/auth/menu", token: adminToken)
            let hidden = try APITestHelpers.decodeBody(PaginatedMenuItems.self, from: res)
            #expect(!hidden.items.contains(where: { $0.id == item.id }))

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/menu?includeDeleted=true", token: adminToken)
            let shown = try APITestHelpers.decodeBody(PaginatedMenuItems.self, from: res)
            #expect(shown.items.contains(where: { $0.id == item.id }))
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

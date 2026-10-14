//
//  SupportTicketTests.swift
//  ApiTests
//
//  TDD: support ticket create / list scope / admin status / delete.
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct SupportTicketTests {

    @Test func createStampsOwnerAndOpensTicket() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-create-admin@example.com") { app in
            let (user, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-create-guest@example.com")
            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token,
                body: CreateSupportTicketRequest(message: "Order never arrived"))
            #expect(res.status == .ok || res.status == .created)
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: res)
            #expect(ticket.status == .open)
            #expect(ticket.creatorUserId == user.id)
            #expect(ticket.message == "Order never arrived")
            #expect(!ticket.id.isEmpty)
        }
    }

    @Test func emptyMessageRejected() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-empty-admin@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-empty-guest@example.com")
            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token,
                body: CreateSupportTicketRequest(message: "   "))
            #expect(res.status == .badRequest)
        }
    }

    @Test func nonAdminListsOnlyOwnTickets() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-scope-admin@example.com") { app in
            let (_, aToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-scope-a@example.com")
            let (_, bToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-scope-b@example.com")

            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: aToken, body: CreateSupportTicketRequest(message: "From A"))
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: bToken, body: CreateSupportTicketRequest(message: "From B"))

            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets", token: aToken)
            #expect(res.status == .ok)
            let page = try APITestHelpers.decodeBody(PaginatedSupportTickets.self, from: res)
            #expect(page.items.count == 1)
            #expect(page.items.first?.message == "From A")
        }
    }

    @Test func adminListsAllTickets() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-admin-list@example.com") { app in
            let (_, aToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-admin-list-a@example.com")
            let (_, bToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-admin-list-b@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-admin-list@example.com")

            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: aToken, body: CreateSupportTicketRequest(message: "A"))
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: bToken, body: CreateSupportTicketRequest(message: "B"))

            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets", token: adminToken)
            #expect(res.status == .ok)
            let page = try APITestHelpers.decodeBody(PaginatedSupportTickets.self, from: res)
            #expect(page.items.count >= 2)
        }
    }

    @Test func nonAdminCannotUpdateStatus() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-status-acl-admin@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-status-acl-guest@example.com")
            let create = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token, body: CreateSupportTicketRequest(message: "Help"))
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: create)

            let res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/support/tickets/\(ticket.id)/status",
                token: token,
                body: UpdateSupportTicketStatusRequest(status: .resolved, staffNote: nil))
            #expect(
                res.status == .forbidden
                    || res.status == .unauthorized
                    || res.status.code == 995)
        }
    }

    @Test func adminUpdatesStatusAndStaffNote() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-status-admin@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-status-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-status-admin@example.com")
            let create = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token, body: CreateSupportTicketRequest(message: "Help"))
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: create)

            let res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/support/tickets/\(ticket.id)/status",
                token: adminToken,
                body: UpdateSupportTicketStatusRequest(
                    status: .inProgress, staffNote: "Looking into it"))
            #expect(res.status == .ok)
            let updated = try APITestHelpers.decodeBody(SupportTicket.self, from: res)
            #expect(updated.status == .inProgress)
            #expect(updated.staffNote == "Looking into it")
        }
    }

    @Test func getByIdOwnerOrAdminOnly() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-get-admin@example.com") { app in
            let (_, ownerToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-get-owner@example.com")
            let (_, otherToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-get-other@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-get-admin@example.com")

            let create = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: ownerToken, body: CreateSupportTicketRequest(message: "Private"))
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: create)

            var res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets/\(ticket.id)", token: otherToken)
            #expect(res.status == .forbidden || res.status.code == 995)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets/\(ticket.id)", token: ownerToken)
            #expect(res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets/\(ticket.id)", token: adminToken)
            #expect(res.status == .ok)
        }
    }

    @Test func guestArchiveHidesFromSelfButAdminStillSees() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-arch-admin@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-arch-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-arch-admin@example.com")

            let create = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token, body: CreateSupportTicketRequest(message: "Archive me"))
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: create)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets/\(ticket.id)/archive", token: token)
            #expect(res.status == .ok)
            let archived = try APITestHelpers.decodeBody(SupportTicket.self, from: res)
            #expect(archived.hiddenByCreatorAt != nil)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets", token: token)
            let mine = try APITestHelpers.decodeBody(PaginatedSupportTickets.self, from: res)
            #expect(mine.items.allSatisfy { $0.id != ticket.id })

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets", token: adminToken)
            let desk = try APITestHelpers.decodeBody(PaginatedSupportTickets.self, from: res)
            #expect(desk.items.contains { $0.id == ticket.id && $0.hiddenByCreatorAt != nil })
        }
    }

    @Test func adminSoftDeleteHidesFromDeskHardRemoves() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-del-admin@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-del-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-del-admin@example.com")

            let create = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token, body: CreateSupportTicketRequest(message: "Delete me"))
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: create)

            var res = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/support/tickets/\(ticket.id)", token: adminToken)
            #expect(res.status == .noContent || res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets", token: adminToken)
            let active = try APITestHelpers.decodeBody(PaginatedSupportTickets.self, from: res)
            #expect(active.items.allSatisfy { $0.id != ticket.id })

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets?includeDeleted=1", token: adminToken)
            let trash = try APITestHelpers.decodeBody(PaginatedSupportTickets.self, from: res)
            #expect(trash.items.contains { $0.id == ticket.id && $0.deletedAt != nil })

            res = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/support/tickets/\(ticket.id)?hard=1", token: adminToken)
            #expect(res.status == .noContent || res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets/\(ticket.id)", token: adminToken)
            #expect(res.status == .notFound)
        }
    }

    @Test func adminCanDeleteGuestArchivedTicket() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-arch-del-admin@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-arch-del-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-arch-del-admin@example.com")

            let create = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token, body: CreateSupportTicketRequest(message: "Archived then deleted"))
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: create)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets/\(ticket.id)/archive", token: token)
            #expect(res.status == .ok)

            res = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/support/tickets/\(ticket.id)", token: adminToken)
            #expect(res.status == .noContent || res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets", token: adminToken)
            let active = try APITestHelpers.decodeBody(PaginatedSupportTickets.self, from: res)
            #expect(active.items.allSatisfy { $0.id != ticket.id })

            res = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/support/tickets/\(ticket.id)?hard=1", token: adminToken)
            #expect(res.status == .noContent || res.status == .ok)

            res = try await APITestHelpers.request(
                app, .GET, "/api/auth/support/tickets/\(ticket.id)", token: adminToken)
            #expect(res.status == .notFound)
        }
    }

    @Test func createAttachesOwnedOrders() async throws {
        try await APITestHelpers.withApp(adminEmail: "support-order-admin@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-order-guest@example.com")
            let (_, otherToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-order-other@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "support-order-admin@example.com")

            let mine = try await APITestHelpers.placeOrder(
                app: app, token: token, customerName: "Guest", adminToken: adminToken)
            let theirs = try await APITestHelpers.placeOrder(
                app: app, token: otherToken, customerName: "Other", adminToken: adminToken)

            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token,
                body: CreateSupportTicketRequest(
                    message: "Wrong drink", relatedOrderIds: [mine.id]))
            #expect(res.status == .ok || res.status == .created)
            let ticket = try APITestHelpers.decodeBody(SupportTicket.self, from: res)
            #expect(ticket.relatedOrderIds ?? [] == [mine.id])

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/support/tickets",
                token: token,
                body: CreateSupportTicketRequest(
                    message: "Not my order", relatedOrderIds: [theirs.id]))
            #expect(
                res.status == .forbidden
                    || res.status == .unauthorized
                    || res.status.code == 995)
        }
    }
}

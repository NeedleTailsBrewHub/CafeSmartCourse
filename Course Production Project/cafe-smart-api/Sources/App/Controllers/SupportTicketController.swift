//
//  SupportTicketController.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Vapor

actor SupportTicketController {
    private static let maxRelatedOrders = 5

    func list(req: Request) async throws -> PaginatedSupportTickets {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        let desk = isMerchantDesk(req)
        let scope = req.query[String.self, at: "scope"]?.lowercased()
        let forceMine = scope == "mine"
        let ownerScope: String? = (forceMine || !desk) ? user.id : nil
        var filter = try SupportTicketListFilter.from(req: req)
        if let ownerScope {
            filter.creatorUserId = ownerScope
            // Guests never see tickets they archived, or admin soft-deleted rows.
            filter.excludeHiddenByCreator = true
            filter.excludeSoftDeleted = true
        } else {
            // Admin desk: still see guest-archived tickets; soft-deleted only with includeDeleted.
            filter.excludeHiddenByCreator = false
        }
        let page = try await req.store.pageSupportTickets(filter: filter)
        return PaginatedSupportTickets(items: page.items, page: page.page)
    }

    func create(req: Request) async throws -> SupportTicket {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        let body = try req.content.decode(CreateSupportTicketRequest.self)
        let message = body.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw Abort(.badRequest, reason: "Message is required")
        }
        let relatedOrderIds = try await resolveRelatedOrderIds(
            req: req, user: user, raw: body.relatedOrderIds)
        let now = Date()
        let ticket = SupportTicket(
            id: ObjectId().hexString,
            creatorUserId: user.id,
            creatorEmail: user.email,
            message: message,
            status: .open,
            createdAt: now,
            updatedAt: now,
            relatedOrderIds: relatedOrderIds.isEmpty ? nil : relatedOrderIds)
        let created = try await req.store.create(supportTicket: ticket)
        try? await AuditService.write(
            req: req, entityType: "supportTicket", entityId: created.id, action: "create",
            summary: String(created.message.prefix(80)))
        return created
    }

    func get(req: Request) async throws -> SupportTicket {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        guard let ticket = try await req.store.findSupportTicket(by: id) else {
            throw Abort(.notFound)
        }
        try requireOwnerOrDesk(req, ticket: ticket)
        let desk = isMerchantDesk(req)
        if !desk {
            if ticket.hiddenByCreatorAt != nil || ticket.deletedAt != nil {
                throw Abort(.notFound)
            }
        }
        return ticket
    }

    func updateStatus(req: Request) async throws -> SupportTicket {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        guard var ticket = try await req.store.findSupportTicket(by: id) else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(UpdateSupportTicketStatusRequest.self)
        ticket.status = body.status
        if let note = body.staffNote {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            ticket.staffNote = trimmed.isEmpty ? nil : trimmed
        }
        ticket.updatedAt = Date()
        let updated = try await req.store.update(supportTicket: ticket)
        try? await AuditService.write(
            req: req, entityType: "supportTicket", entityId: updated.id, action: "status",
            summary: "status=\(updated.status.rawValue)")
        return updated
    }

    /// Guest: hide from their inbox (admin still sees it).
    func archive(req: Request) async throws -> SupportTicket {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        guard var ticket = try await req.store.findSupportTicket(by: id) else {
            throw Abort(.notFound)
        }
        guard ticket.creatorUserId == user.id else {
            throw Abort(.forbidden, reason: "Not allowed to archive this ticket")
        }
        if ticket.hiddenByCreatorAt == nil {
            ticket.hiddenByCreatorAt = Date()
            ticket.updatedAt = Date()
            ticket = try await req.store.update(supportTicket: ticket)
            try? await AuditService.write(
                req: req, entityType: "supportTicket", entityId: ticket.id, action: "archive",
                summary: "hiddenByCreator")
        }
        return ticket
    }

    /// Admin soft-delete (default) or hard-delete (`?hard=1`).
    /// Works for guest-archived tickets too.
    /// Owner DELETE is treated as archive (hide from guest inbox only).
    func delete(req: Request) async throws -> HTTPStatus {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        guard var ticket = try await req.store.findSupportTicket(by: id) else {
            throw Abort(.notFound)
        }
        let desk = isMerchantDesk(req)
        if !desk {
            guard ticket.creatorUserId == user.id else {
                throw Abort(.forbidden, reason: "Not allowed to remove this ticket")
            }
            if ticket.hiddenByCreatorAt == nil {
                ticket.hiddenByCreatorAt = Date()
                ticket.updatedAt = Date()
                _ = try await req.store.update(supportTicket: ticket)
                try? await AuditService.write(
                    req: req, entityType: "supportTicket", entityId: id, action: "archive",
                    summary: "hiddenByCreator")
            }
            return .noContent
        }

        let hard = ListQuery.flag(req, "hard")
        if hard {
            try await req.store.deleteSupportTicket(id: id)
            try? await AuditService.write(
                req: req, entityType: "supportTicket", entityId: id, action: "hardDelete",
                summary: ticket.hiddenByCreatorAt != nil ? "guestArchived" : nil)
        } else {
            if ticket.deletedAt == nil {
                ticket.deletedAt = Date()
                ticket.updatedAt = Date()
                _ = try await req.store.update(supportTicket: ticket)
                try? await AuditService.write(
                    req: req, entityType: "supportTicket", entityId: id, action: "softDelete",
                    summary: ticket.hiddenByCreatorAt != nil ? "guestArchived" : nil)
            }
        }
        return .noContent
    }

    private func resolveRelatedOrderIds(
        req: Request, user: User, raw: [String]?
    ) async throws -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var seen = Set<String>()
        var ids: [String] = []
        for rawId in raw {
            let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            ids.append(id)
        }
        guard ids.count <= Self.maxRelatedOrders else {
            throw Abort(
                .badRequest,
                reason: "At most \(Self.maxRelatedOrders) related orders allowed")
        }
        let desk = RoleGate.isMerchantFloor(
            for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)
        for id in ids {
            guard let order = try await req.store.findOrder(by: id) else {
                throw Abort(.badRequest, reason: "Unknown order \(id)")
            }
            if !desk {
                guard order.customerUserId == user.id else {
                    throw Abort(.forbidden, reason: "Not allowed to attach order \(id)")
                }
            }
        }
        return ids
    }

    private func isMerchantDesk(_ req: Request) -> Bool {
        RoleGate.isMerchantFloor(req: req)
    }

    private func requireOwnerOrDesk(_ req: Request, ticket: SupportTicket) throws {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        let desk = RoleGate.isMerchantFloor(
            for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)
        guard desk || ticket.creatorUserId == user.id else {
            throw Abort(.forbidden, reason: "Not allowed to view this ticket")
        }
    }
}

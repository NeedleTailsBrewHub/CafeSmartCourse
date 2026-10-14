//
//  AuditController.swift
//  CafeSmartAPI
//

import Vapor

actor AuditController {
    func list(req: Request) async throws -> PaginatedAuditEvents {
        let filter = try AuditListFilter.from(req: req)
        let page = try await req.store.pageAuditEvents(filter: filter)
        return PaginatedAuditEvents(items: page.items, page: page.page)
    }
}

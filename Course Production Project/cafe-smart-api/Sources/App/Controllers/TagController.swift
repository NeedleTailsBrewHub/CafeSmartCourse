//
//  TagController.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Vapor

actor TagController {
    func listGroups(req: Request) async throws -> PaginatedTagGroups {
        let filter = try TagGroupListFilter.from(req: req)
        let page = try await req.store.pageTagGroups(filter: filter)
        return PaginatedTagGroups(items: page.items, page: page.page)
    }

    func createGroup(req: Request) async throws -> TagGroup {
        let body = try req.content.decode(CreateTagGroupRequest.self)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Abort(.badRequest, reason: "Name required") }
        let existing = try await req.store.listTagGroups()
        if TagValidation.groupNameConflict(existing: existing, name: name, excludingId: nil) {
            throw Abort(.conflict, reason: "Tag group name already exists")
        }
        let now = Date()
        let group = TagGroup(
            id: ObjectId().hexString,
            name: name,
            slug: body.slug,
            sortOrder: body.sortOrder ?? 0,
            allowsMultiple: body.allowsMultiple ?? true,
            createdAt: now,
            updatedAt: now)
        let created = try await req.store.createTagGroup(group)
        try await AuditService.write(
            req: req, entityType: "tagGroup", entityId: created.id, action: "create",
            summary: created.name)
        return created
    }

    func updateGroup(req: Request) async throws -> TagGroup {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        guard var group = try await req.store.findTagGroup(by: id) else { throw Abort(.notFound) }
        let body = try req.content.decode(UpdateTagGroupRequest.self)
        if let name = body.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !name.isEmpty else { throw Abort(.badRequest, reason: "Name required") }
            let existing = try await req.store.listTagGroups()
            if TagValidation.groupNameConflict(existing: existing, name: name, excludingId: id) {
                throw Abort(.conflict, reason: "Tag group name already exists")
            }
            group.name = name
        }
        if let slug = body.slug { group.slug = slug }
        if let sortOrder = body.sortOrder { group.sortOrder = sortOrder }
        if let allowsMultiple = body.allowsMultiple { group.allowsMultiple = allowsMultiple }
        if let isArchived = body.isArchived { group.isArchived = isArchived }
        group.updatedAt = Date()
        let updated = try await req.store.updateTagGroup(group)
        try await AuditService.write(
            req: req, entityType: "tagGroup", entityId: updated.id, action: "update",
            summary: updated.name)
        return updated
    }

    func archiveGroup(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        try await req.store.archiveTagGroup(id: id, at: Date())
        try await AuditService.write(
            req: req, entityType: "tagGroup", entityId: id, action: "archive")
        return .noContent
    }

    func listTags(req: Request) async throws -> PaginatedTags {
        let filter = try TagListFilter.from(req: req)
        let page = try await req.store.pageTags(filter: filter)
        return PaginatedTags(items: page.items, page: page.page)
    }

    func listTagsInGroup(req: Request) async throws -> PaginatedTags {
        guard let groupId = req.parameters.get("id") else { throw Abort(.badRequest) }
        let filter = try TagListFilter.from(req: req, groupId: groupId)
        let page = try await req.store.pageTags(filter: filter)
        return PaginatedTags(items: page.items, page: page.page)
    }

    func createTag(req: Request) async throws -> Tag {
        let body = try req.content.decode(CreateTagRequest.self)
        guard try await req.store.findTagGroup(by: body.groupId) != nil else {
            throw Abort(.badRequest, reason: "Unknown tag group")
        }
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Abort(.badRequest, reason: "Name required") }
        let existing = try await req.store.listTags()
        if TagValidation.tagNameConflict(
            existing: existing, groupId: body.groupId, name: name, excludingId: nil)
        {
            throw Abort(.conflict, reason: "Tag name already exists in group")
        }
        let now = Date()
        let tag = Tag(
            id: ObjectId().hexString,
            groupId: body.groupId,
            name: name,
            slug: body.slug,
            color: body.color,
            sortOrder: body.sortOrder ?? 0,
            createdAt: now,
            updatedAt: now)
        let created = try await req.store.createTag(tag)
        try await AuditService.write(
            req: req, entityType: "tag", entityId: created.id, action: "create",
            summary: created.name)
        return created
    }

    func updateTag(req: Request) async throws -> Tag {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        guard var tag = try await req.store.findTag(by: id) else { throw Abort(.notFound) }
        let body = try req.content.decode(UpdateTagRequest.self)
        if let name = body.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !name.isEmpty else { throw Abort(.badRequest, reason: "Name required") }
            let existing = try await req.store.listTags()
            if TagValidation.tagNameConflict(
                existing: existing, groupId: tag.groupId, name: name, excludingId: id)
            {
                throw Abort(.conflict, reason: "Tag name already exists in group")
            }
            tag.name = name
        }
        if let slug = body.slug { tag.slug = slug }
        if let color = body.color { tag.color = color }
        if let sortOrder = body.sortOrder { tag.sortOrder = sortOrder }
        if let isArchived = body.isArchived { tag.isArchived = isArchived }
        tag.updatedAt = Date()
        let updated = try await req.store.updateTag(tag)
        try await AuditService.write(
            req: req, entityType: "tag", entityId: updated.id, action: "update",
            summary: updated.name)
        return updated
    }

    func archiveTag(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        try await req.store.archiveTag(id: id, at: Date())
        try await AuditService.write(req: req, entityType: "tag", entityId: id, action: "archive")
        return .noContent
    }
}

//
//  ListFilters.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

public struct OrderListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var q: String?
    public var status: OrderStatus?
    /// When non-empty, match any of these statuses (`statuses=pending,preparing`).
    public var statuses: [OrderStatus]
    public var from: Date?
    public var to: Date?
    public var customerUserId: String?

    public init(
        limit: Int = 25,
        cursor: ListCursor? = nil,
        q: String? = nil,
        status: OrderStatus? = nil,
        statuses: [OrderStatus] = [],
        from: Date? = nil,
        to: Date? = nil,
        customerUserId: String? = nil
    ) {
        self.limit = limit
        self.cursor = cursor
        self.q = q
        self.status = status
        self.statuses = statuses
        self.from = from
        self.to = to
        self.customerUserId = customerUserId
    }

    public static func from(req: Request, customerUserId: String?) throws -> OrderListFilter {
        var fromDate: Date?
        var toDate: Date?
        if let raw = req.query[String.self, at: "from"], let d = ISO8601DateFormatter().date(from: raw) {
            fromDate = d
        }
        if let raw = req.query[String.self, at: "to"], let d = ISO8601DateFormatter().date(from: raw) {
            toDate = d
        }
        let statusRaw = req.query[String.self, at: "status"]
        var statuses: [OrderStatus] = []
        if let many = req.query[String.self, at: "statuses"], !many.isEmpty {
            statuses = many.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap(OrderStatus.init(rawValue:))
        }
        return OrderListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            q: ListQuery.q(from: req),
            status: statusRaw.flatMap(OrderStatus.init(rawValue:)),
            statuses: statuses,
            from: fromDate,
            to: toDate,
            customerUserId: customerUserId)
    }
}

public struct MenuListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var q: String?
    public var category: String?
    public var isAvailable: Bool?
    public var tagIds: Set<String>
    public var tagGroupId: String?
    public var includeDeleted: Bool

    public init(
        limit: Int = 25,
        cursor: ListCursor? = nil,
        q: String? = nil,
        category: String? = nil,
        isAvailable: Bool? = nil,
        tagIds: Set<String> = [],
        tagGroupId: String? = nil,
        includeDeleted: Bool = false
    ) {
        self.limit = limit
        self.cursor = cursor
        self.q = q
        self.category = category
        self.isAvailable = isAvailable
        self.tagIds = tagIds
        self.tagGroupId = tagGroupId
        self.includeDeleted = includeDeleted
    }

    public static func from(req: Request) throws -> MenuListFilter {
        var tagIds = Set<String>()
        if let one = req.query[String.self, at: "tagId"], !one.isEmpty { tagIds.insert(one) }
        if let many = req.query[String.self, at: "tagIds"], !many.isEmpty {
            many.split(separator: ",").map(String.init).forEach { tagIds.insert($0) }
        }
        let availRaw = req.query[String.self, at: "isAvailable"]?.lowercased()
        let isAvailable: Bool? = {
            guard let availRaw else { return nil }
            if availRaw == "true" || availRaw == "1" { return true }
            if availRaw == "false" || availRaw == "0" { return false }
            return nil
        }()
        return MenuListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            q: ListQuery.q(from: req),
            category: req.query[String.self, at: "category"],
            isAvailable: isAvailable,
            tagIds: tagIds,
            tagGroupId: req.query[String.self, at: "tagGroupId"],
            includeDeleted: ListQuery.flag(req, "includeDeleted"))
    }
}

public struct InventoryListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var q: String?
    public var lowStock: Bool
    public var storage: InventoryItem.StorageType?
    public var tagIds: Set<String>
    public var tagGroupId: String?
    public var includeDeleted: Bool

    public init(
        limit: Int = 25,
        cursor: ListCursor? = nil,
        q: String? = nil,
        lowStock: Bool = false,
        storage: InventoryItem.StorageType? = nil,
        tagIds: Set<String> = [],
        tagGroupId: String? = nil,
        includeDeleted: Bool = false
    ) {
        self.limit = limit
        self.cursor = cursor
        self.q = q
        self.lowStock = lowStock
        self.storage = storage
        self.tagIds = tagIds
        self.tagGroupId = tagGroupId
        self.includeDeleted = includeDeleted
    }

    public static func from(req: Request) throws -> InventoryListFilter {
        var tagIds = Set<String>()
        if let one = req.query[String.self, at: "tagId"], !one.isEmpty { tagIds.insert(one) }
        if let many = req.query[String.self, at: "tagIds"], !many.isEmpty {
            many.split(separator: ",").map(String.init).forEach { tagIds.insert($0) }
        }
        let storageRaw = req.query[String.self, at: "storage"]
        return InventoryListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            q: ListQuery.q(from: req),
            lowStock: ListQuery.flag(req, "lowStock"),
            storage: storageRaw.flatMap(InventoryItem.StorageType.init(rawValue:)),
            tagIds: tagIds,
            tagGroupId: req.query[String.self, at: "tagGroupId"],
            includeDeleted: ListQuery.flag(req, "includeDeleted"))
    }
}

public struct ReservationListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var q: String?
    public var status: ReservationStatus?
    public var from: Date?
    public var to: Date?
    public var customerUserId: String?

    public init(
        limit: Int = 25,
        cursor: ListCursor? = nil,
        q: String? = nil,
        status: ReservationStatus? = nil,
        from: Date? = nil,
        to: Date? = nil,
        customerUserId: String? = nil
    ) {
        self.limit = limit
        self.cursor = cursor
        self.q = q
        self.status = status
        self.from = from
        self.to = to
        self.customerUserId = customerUserId
    }

    public static func from(req: Request, customerUserId: String?) throws -> ReservationListFilter {
        var fromDate: Date?
        var toDate: Date?
        if let raw = req.query[String.self, at: "from"], let d = ISO8601DateFormatter().date(from: raw) {
            fromDate = d
        }
        if let raw = req.query[String.self, at: "to"], let d = ISO8601DateFormatter().date(from: raw) {
            toDate = d
        }
        let statusRaw = req.query[String.self, at: "status"]
        return ReservationListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            q: ListQuery.q(from: req),
            status: statusRaw.flatMap(ReservationStatus.init(rawValue:)),
            from: fromDate,
            to: toDate,
            customerUserId: customerUserId)
    }
}

public struct TagGroupListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var q: String?
    public var includeArchived: Bool

    public init(limit: Int = 25, cursor: ListCursor? = nil, q: String? = nil, includeArchived: Bool = false) {
        self.limit = limit
        self.cursor = cursor
        self.q = q
        self.includeArchived = includeArchived
    }

    public static func from(req: Request) throws -> TagGroupListFilter {
        TagGroupListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            q: ListQuery.q(from: req),
            includeArchived: ListQuery.flag(req, "includeArchived"))
    }
}

public struct TagListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var q: String?
    public var groupId: String?
    public var includeArchived: Bool

    public init(
        limit: Int = 25,
        cursor: ListCursor? = nil,
        q: String? = nil,
        groupId: String? = nil,
        includeArchived: Bool = false
    ) {
        self.limit = limit
        self.cursor = cursor
        self.q = q
        self.groupId = groupId
        self.includeArchived = includeArchived
    }

    public static func from(req: Request, groupId: String? = nil) throws -> TagListFilter {
        TagListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            q: ListQuery.q(from: req),
            groupId: groupId ?? req.query[String.self, at: "groupId"],
            includeArchived: ListQuery.flag(req, "includeArchived"))
    }
}

public struct AuditListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var entityType: String?
    public var entityId: String?

    public init(limit: Int = 25, cursor: ListCursor? = nil, entityType: String? = nil, entityId: String? = nil) {
        self.limit = limit
        self.cursor = cursor
        self.entityType = entityType
        self.entityId = entityId
    }

    public static func from(req: Request) throws -> AuditListFilter {
        AuditListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            entityType: req.query[String.self, at: "entityType"],
            entityId: req.query[String.self, at: "entityId"])
    }
}

public struct SupportTicketListFilter: Sendable {
    public var limit: Int
    public var cursor: ListCursor?
    public var q: String?
    public var status: SupportTicketStatus?
    public var creatorUserId: String?
    /// When true, omit tickets the guest archived from their inbox.
    public var excludeHiddenByCreator: Bool
    /// When true, omit admin soft-deleted tickets.
    public var excludeSoftDeleted: Bool

    public init(
        limit: Int = 25,
        cursor: ListCursor? = nil,
        q: String? = nil,
        status: SupportTicketStatus? = nil,
        creatorUserId: String? = nil,
        excludeHiddenByCreator: Bool = false,
        excludeSoftDeleted: Bool = true
    ) {
        self.limit = limit
        self.cursor = cursor
        self.q = q
        self.status = status
        self.creatorUserId = creatorUserId
        self.excludeHiddenByCreator = excludeHiddenByCreator
        self.excludeSoftDeleted = excludeSoftDeleted
    }

    public static func from(req: Request) throws -> SupportTicketListFilter {
        let statusRaw = req.query[String.self, at: "status"]
        let status = statusRaw.flatMap { SupportTicketStatus(rawValue: $0) }
        return SupportTicketListFilter(
            limit: ListQuery.limit(from: req),
            cursor: try ListQuery.cursor(from: req),
            q: ListQuery.q(from: req),
            status: status,
            creatorUserId: req.query[String.self, at: "creatorUserId"],
            excludeHiddenByCreator: false,
            excludeSoftDeleted: !ListQuery.flag(req, "includeDeleted"))
    }
}

enum ListSearch {
    static func matches(_ field: String, q: String) -> Bool {
        field.localizedCaseInsensitiveContains(q)
    }

    static func matchesAny(q: String, fields: [String]) -> Bool {
        fields.contains { matches($0, q: q) }
    }
}

enum ListPagination {
    static func page<T>(
        _ items: [T],
        limit: Int,
        cursor: ListCursor?,
        sortKey: (T) -> String,
        id: KeyPath<T, String>,
        ascending: Bool
    ) throws -> PageResult<T> {
        try PageSlice.apply(
            items,
            limit: limit,
            cursor: cursor,
            sortKey: sortKey,
            idKey: { $0[keyPath: id] },
            ascending: ascending)
    }
}

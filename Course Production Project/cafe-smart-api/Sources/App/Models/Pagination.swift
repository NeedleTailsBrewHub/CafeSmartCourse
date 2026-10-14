//
//  Pagination.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

public struct PageInfo: Content, Sendable, Equatable {
    public var nextCursor: String?
    public var hasMore: Bool
    public var limit: Int

    public init(nextCursor: String? = nil, hasMore: Bool, limit: Int) {
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.limit = limit
    }
}

public struct PageResult<T: Sendable>: Sendable {
    public var items: [T]
    public var page: PageInfo

    public init(items: [T], page: PageInfo) {
        self.items = items
        self.page = page
    }
}

/// Opaque cursor: base64url JSON `{"t":"<sort>","id":"<id>"}`.
public struct ListCursor: Codable, Sendable, Equatable {
    public var t: String
    public var id: String

    public init(t: String, id: String) {
        self.t = t
        self.id = id
    }

    public func encode() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ raw: String?) throws -> ListCursor? {
        guard let raw, !raw.isEmpty else { return nil }
        var s = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else {
            throw Abort(.badRequest, reason: "Invalid cursor")
        }
        return try JSONDecoder().decode(ListCursor.self, from: data)
    }
}

public enum ListQuery {
    public static func limit(from req: Request, default defaultLimit: Int = 25) -> Int {
        let raw = req.query[Int.self, at: "limit"] ?? defaultLimit
        return min(100, max(1, raw))
    }

    public static func q(from req: Request) -> String? {
        let raw = (req.query[String.self, at: "q"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    public static func cursor(from req: Request) throws -> ListCursor? {
        try ListCursor.decode(req.query[String.self, at: "cursor"])
    }

    public static func flag(_ req: Request, _ name: String) -> Bool {
        guard let v = req.query[String.self, at: name]?.lowercased() else { return false }
        return v == "1" || v == "true" || v == "yes"
    }
}

public struct PaginatedOrders: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [Order]
    public var page: PageInfo
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct PaginatedMenuItems: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [MenuItem]
    public var page: PageInfo
    /// Monotonic menu catalog revision at list time.
    public var catalogVersion: Int64 = 0
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct PaginatedInventoryItems: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [InventoryItem]
    public var page: PageInfo
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct PaginatedReservations: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [Reservation]
    public var page: PageInfo
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct PaginatedTagGroups: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [TagGroup]
    public var page: PageInfo
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct PaginatedTags: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [Tag]
    public var page: PageInfo
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct PaginatedAuditEvents: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [AuditEvent]
    public var page: PageInfo
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct PaginatedSupportTickets: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [SupportTicket]
    public var page: PageInfo
    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Shared paging helper for in-memory stores and simple Mongo scans.
enum PageSlice {
    static func apply<T>(
        _ items: [T],
        limit: Int,
        cursor: ListCursor?,
        sortKey: (T) -> String,
        idKey: (T) -> String,
        ascending: Bool
    ) throws -> PageResult<T> {
        var sorted = items.sorted { a, b in
            let ka = sortKey(a), kb = sortKey(b)
            if ka != kb {
                return ascending ? ka < kb : ka > kb
            }
            let ia = idKey(a), ib = idKey(b)
            return ascending ? ia < ib : ia > ib
        }
        if let cursor {
            sorted = sorted.filter { item in
                let k = sortKey(item)
                let i = idKey(item)
                if ascending {
                    if k != cursor.t { return k > cursor.t }
                    return i > cursor.id
                } else {
                    if k != cursor.t { return k < cursor.t }
                    return i < cursor.id
                }
            }
        }
        let hasMore = sorted.count > limit
        let pageItems = Array(sorted.prefix(limit))
        var next: String?
        if hasMore, let last = pageItems.last {
            next = try ListCursor(t: sortKey(last), id: idKey(last)).encode()
        }
        return PageResult(
            items: pageItems,
            page: PageInfo(nextCursor: next, hasMore: hasMore, limit: limit))
    }
}

//
//  TagTaxonomy.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

public struct TagGroup: Content, Sendable, Equatable, Identifiable, BinaryResponseEncodable {
    public var id: String
    public var name: String
    public var slug: String?
    public var sortOrder: Int
    public var allowsMultiple: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        slug: String? = nil,
        sortOrder: Int = 0,
        allowsMultiple: Bool = true,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.sortOrder = sortOrder
        self.allowsMultiple = allowsMultiple
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct Tag: Content, Sendable, Equatable, Identifiable, BinaryResponseEncodable {
    public var id: String
    public var groupId: String
    public var name: String
    public var slug: String?
    public var color: String?
    public var sortOrder: Int
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        groupId: String,
        name: String,
        slug: String? = nil,
        color: String? = nil,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.groupId = groupId
        self.name = name
        self.slug = slug
        self.color = color
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct CreateTagGroupRequest: Content, Sendable {
    public var name: String
    public var slug: String?
    public var sortOrder: Int?
    public var allowsMultiple: Bool?

    public init(name: String, slug: String? = nil, sortOrder: Int? = nil, allowsMultiple: Bool? = nil) {
        self.name = name
        self.slug = slug
        self.sortOrder = sortOrder
        self.allowsMultiple = allowsMultiple
    }
}

public struct UpdateTagGroupRequest: Content, Sendable {
    public var name: String?
    public var slug: String?
    public var sortOrder: Int?
    public var allowsMultiple: Bool?
    public var isArchived: Bool?
}

public struct CreateTagRequest: Content, Sendable {
    public var groupId: String
    public var name: String
    public var slug: String?
    public var color: String?
    public var sortOrder: Int?

    public init(
        groupId: String,
        name: String,
        slug: String? = nil,
        color: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.groupId = groupId
        self.name = name
        self.slug = slug
        self.color = color
        self.sortOrder = sortOrder
    }
}

public struct UpdateTagRequest: Content, Sendable {
    public var name: String?
    public var slug: String?
    public var color: String?
    public var sortOrder: Int?
    public var isArchived: Bool?
}

public struct BulkResult: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var updated: Int
    public var errors: [String]

    public init(updated: Int, errors: [String] = []) {
        self.updated = updated
        self.errors = errors
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct CSVImportResult: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var upserted: Int
    public var errors: [String]

    public init(upserted: Int, errors: [String] = []) {
        self.upserted = upserted
        self.errors = errors
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct CSVExportPayload: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var csv: String

    public init(csv: String) {
        self.csv = csv
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct CSVImportRequest: Content, Sendable {
    public var csv: String
}

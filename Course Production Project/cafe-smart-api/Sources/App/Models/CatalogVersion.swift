//
//  CatalogVersion.swift
//  CafeSmartAPI
//
//  Monotonic menu catalog revision for client stale detection.
//

import Foundation
import Vapor

public struct CatalogVersion: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var version: Int64
    public var updatedAt: Date

    public init(version: Int64, updatedAt: Date = Date()) {
        self.version = version
        self.updatedAt = updatedAt
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Persisted singleton document (id = "menu").
public struct CatalogMeta: Content, Sendable, Equatable {
    public static let menuId = "menu"

    public var id: String
    public var version: Int64
    public var updatedAt: Date

    public init(id: String = CatalogMeta.menuId, version: Int64 = 0, updatedAt: Date = Date()) {
        self.id = id
        self.version = version
        self.updatedAt = updatedAt
    }

    public var asVersion: CatalogVersion {
        CatalogVersion(version: version, updatedAt: updatedAt)
    }
}

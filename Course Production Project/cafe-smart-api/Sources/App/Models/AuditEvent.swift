//
//  AuditEvent.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

public struct AuditEvent: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var entityType: String
	public var entityId: String
	public var action: String
	public var userId: String?
	public var summary: String?
	public var createdAt: Date

	public init(
		id: String,
		entityType: String,
		entityId: String,
		action: String,
		userId: String? = nil,
		summary: String? = nil,
		createdAt: Date
	) {
		self.id = id
		self.entityType = entityType
		self.entityId = entityId
		self.action = action
		self.userId = userId
		self.summary = summary
		self.createdAt = createdAt
	}

	public func encodeResponse(for request: Request) async throws -> Response {
		try binaryEncodedResponse()
	}
}

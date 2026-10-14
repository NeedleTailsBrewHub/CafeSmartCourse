//
//  AuditService.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Vapor

enum AuditService {
	static func write(
		req: Request,
		entityType: String,
		entityId: String,
		action: String,
		summary: String? = nil
	) async throws {
		let userId = req.storage.get(UserKey.self)?.id
		let event = AuditEvent(
			id: ObjectId().hexString,
			entityType: entityType,
			entityId: entityId,
			action: action,
			userId: userId,
			summary: summary,
			createdAt: Date())
		try await req.store.createAuditEvent(event)
	}
}

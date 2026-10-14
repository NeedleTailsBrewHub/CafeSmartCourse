//
//  LoyaltyController.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is licensed under the MIT License.
//
//  See the LICENSE file for more information.
//
//  This file is part of the CafeSmartAPI Project

@preconcurrency import BSON
import MongoKitten
import Vapor

private struct DBLoyalty: Codable {
    var _id: ObjectId
    var userId: String
    var points: Int
    var tier: String
    var createdAt: Date
}

struct LoyaltyEnrollRequest: Content {
    var userId: String?
    var email: String?
}

struct LoyaltyAccrueRequest: Content {
    var userId: String?
    var email: String?
    var points: Int
}

struct LoyaltyRedeemRequest: Content {
    var userId: String?
    var email: String?
    var points: Int
}

struct LoyaltyAccountPublic: Content, BinaryResponseEncodable {
    let id: String
    let userId: String
    let points: Int
    let tier: String

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

actor LoyaltyController {
    private let collection = LoyaltyLedger.collection

    private func loadMemory(_ app: Application) -> [DBLoyalty] {
        app.storage[LoyaltyLedger.MemoryKey.self] ?? []
    }

    private func saveMemory(_ app: Application, _ accounts: [DBLoyalty]) {
        app.storage[LoyaltyLedger.MemoryKey.self] = accounts
    }
    
    private func requireLoyaltyAccess(req: Request, targetUserId: String) throws {
        guard let actor = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        let isAdmin = AdminEnv.isAdmin(
            user: actor, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)
        guard isAdmin || actor.id == targetUserId else { throw Abort(.forbidden) }
    }

    /// Accrue/redeem are admin desk only — guests/staff/managers must not mint or burn points.
    private func requireLoyaltyAdmin(req: Request) throws {
        try RoleGate.requireAdmin(req: req)
    }

    /// Resolve `userId` or customer `email` for merchant desk + self-serve flows.
    private func resolveTargetUserId(req: Request, userId: String?, email: String?) async throws -> String {
        if let userId, !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return userId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let user = try await req.store.findUser(byEmail: lower) else {
                throw Abort(.notFound, reason: "No account for that email")
            }
            return user.id
        }
        throw Abort(.badRequest, reason: "Provide userId or email")
    }

    private func accountPublic(for userId: String, req: Request) async throws -> LoyaltyAccountPublic {
        if req.application.environment == .testing {
            let accounts = loadMemory(req.application)
            guard let acc = accounts.first(where: { $0.userId == userId }) else {
                throw Abort(.notFound)
            }
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        }
        let coll = req.mongoDB[collection]
        guard let doc = try await coll.findOne("userId" == userId) else { throw Abort(.notFound) }
        let acc = try BSONDecoder().decode(DBLoyalty.self, from: doc)
        return LoyaltyAccountPublic(
            id: acc._id.hexString,
            userId: acc.userId,
            points: acc.points,
            tier: acc.tier)
    }

    func enroll(req: Request) async throws -> LoyaltyAccountPublic {
        let body = try req.content.decode(LoyaltyEnrollRequest.self)
        let userId = try await resolveTargetUserId(req: req, userId: body.userId, email: body.email)
        try requireLoyaltyAccess(req: req, targetUserId: userId)
        try await LoyaltyLedger.ensureAccount(req: req, userId: userId)
        return try await accountPublic(for: userId, req: req)
    }
    
    func get(req: Request) async throws -> LoyaltyAccountPublic {
        // `:id` accepts loyalty account ObjectId hex or the user's id string.
        // User ids are also ObjectId hex, so fall back to userId when `_id` misses.
        guard let id = req.parameters.get("id"), !id.isEmpty else { throw Abort(.badRequest) }
        if req.application.environment == .testing {
            let accounts = loadMemory(req.application)
            let acc =
                accounts.first(where: { $0._id.hexString == id })
                ?? accounts.first(where: { $0.userId == id })
            guard let acc else { throw Abort(.notFound) }
            try requireLoyaltyAccess(req: req, targetUserId: acc.userId)
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        } else {
            let coll = req.mongoDB[collection]
            var doc: Document?
            if let oid = ObjectId(id) {
                doc = try await coll.findOne("_id" == oid)
            }
            if doc == nil {
                doc = try await coll.findOne("userId" == id)
            }
            guard let doc else { throw Abort(.notFound) }
            let acc = try BSONDecoder().decode(DBLoyalty.self, from: doc)
            try requireLoyaltyAccess(req: req, targetUserId: acc.userId)
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        }
    }
    
    func accrue(req: Request) async throws -> LoyaltyAccountPublic {
        try requireLoyaltyAdmin(req: req)
        let body = try req.content.decode(LoyaltyAccrueRequest.self)
        guard body.points > 0 else { throw Abort(.badRequest, reason: "Points must be positive") }
        let userId = try await resolveTargetUserId(req: req, userId: body.userId, email: body.email)
        try await LoyaltyLedger.ensureAndAccrue(req: req, userId: userId, points: body.points)
        try? await AuditService.write(
            req: req, entityType: "loyalty", entityId: userId, action: "accrue",
            summary: "+\(body.points)")
        return try await accountPublic(for: userId, req: req)
    }

    func redeem(req: Request) async throws -> LoyaltyAccountPublic {
        try requireLoyaltyAdmin(req: req)
        let body = try req.content.decode(LoyaltyRedeemRequest.self)
        guard body.points > 0 else { throw Abort(.badRequest, reason: "Points must be positive") }
        let userId = try await resolveTargetUserId(req: req, userId: body.userId, email: body.email)
        try await LoyaltyLedger.ensureAccount(req: req, userId: userId)
        if req.application.environment == .testing {
            var accounts = loadMemory(req.application)
            guard let idx = accounts.firstIndex(where: { $0.userId == userId }) else {
                throw Abort(.notFound)
            }
            guard accounts[idx].points >= body.points else {
                throw Abort(.badRequest, reason: "Insufficient points")
            }
            accounts[idx].points -= body.points
            accounts[idx].tier = LoyaltyLedger.tierFor(points: accounts[idx].points)
            saveMemory(req.application, accounts)
        } else {
            let coll = req.mongoDB[collection]
            guard let doc = try await coll.findOne("userId" == userId) else { throw Abort(.notFound) }
            var acc = try BSONDecoder().decode(DBLoyalty.self, from: doc)
            guard acc.points >= body.points else {
                throw Abort(.badRequest, reason: "Insufficient points")
            }
            acc.points -= body.points
            acc.tier = LoyaltyLedger.tierFor(points: acc.points)
            _ = try await coll.updateOne(where: "_id" == acc._id, to: BSONEncoder().encode(acc))
        }
        try? await AuditService.write(
            req: req, entityType: "loyalty", entityId: userId, action: "redeem",
            summary: "-\(body.points)")
        return try await accountPublic(for: userId, req: req)
    }
}

/// Shared enroll/accrue helpers used by orders + registration (best-effort).
enum LoyaltyLedger {
    static let collection = "loyalty_accounts"

    fileprivate struct MemoryKey: StorageKey {
        typealias Value = [DBLoyalty]
    }

    static func tierFor(points: Int) -> String {
        switch points {
        case 0..<100: return "basic"
        case 100..<300: return "silver"
        case 300..<700: return "gold"
        default: return "platinum"
        }
    }

    /// Ensure an account exists and add points. Errors are swallowed by callers with `try?`.
    static func ensureAndAccrue(req: Request, userId: String, points: Int) async throws {
        guard !userId.isEmpty, points > 0 else { return }
        if req.application.environment == .testing {
            var accounts = req.application.storage[MemoryKey.self] ?? []
            if let idx = accounts.firstIndex(where: { $0.userId == userId }) {
                accounts[idx].points += points
                accounts[idx].tier = tierFor(points: accounts[idx].points)
            } else {
                let oid = ObjectId()
                accounts.append(
                    DBLoyalty(
                        _id: oid,
                        userId: userId,
                        points: points,
                        tier: tierFor(points: points),
                        createdAt: Date()
                    )
                )
            }
            req.application.storage[MemoryKey.self] = accounts
            return
        }
        let coll = req.mongoDB[collection]
        if var acc = try await coll.findOne("userId" == userId).map({
            try BSONDecoder().decode(DBLoyalty.self, from: $0)
        }) {
            acc.points += points
            acc.tier = tierFor(points: acc.points)
            _ = try await coll.updateOne(where: "_id" == acc._id, to: BSONEncoder().encode(acc))
        } else {
            let oid = ObjectId()
            let db = DBLoyalty(
                _id: oid,
                userId: userId,
                points: points,
                tier: tierFor(points: points),
                createdAt: Date()
            )
            try await coll.insert(BSONEncoder().encode(db))
        }
    }

    static func ensureAccount(req: Request, userId: String) async throws {
        guard !userId.isEmpty else { return }
        if req.application.environment == .testing {
            var accounts = req.application.storage[MemoryKey.self] ?? []
            if accounts.contains(where: { $0.userId == userId }) { return }
            accounts.append(
                DBLoyalty(
                    _id: ObjectId(),
                    userId: userId,
                    points: 0,
                    tier: "basic",
                    createdAt: Date()
                )
            )
            req.application.storage[MemoryKey.self] = accounts
            return
        }
        let coll = req.mongoDB[collection]
        if try await coll.findOne("userId" == userId) != nil { return }
        let db = DBLoyalty(
            _id: ObjectId(),
            userId: userId,
            points: 0,
            tier: "basic",
            createdAt: Date()
        )
        try await coll.insert(BSONEncoder().encode(db))
    }

    static func currentPoints(req: Request, userId: String) async throws -> Int {
        guard !userId.isEmpty else { return 0 }
        if req.application.environment == .testing {
            return req.application.storage[MemoryKey.self]?.first(where: { $0.userId == userId })?.points ?? 0
        }
        let coll = req.mongoDB[collection]
        guard let doc = try await coll.findOne("userId" == userId) else { return 0 }
        return try BSONDecoder().decode(DBLoyalty.self, from: doc).points
    }

    static func spend(req: Request, userId: String, points: Int) async throws {
        guard !userId.isEmpty, points > 0 else { return }
        try await ensureAccount(req: req, userId: userId)
        if req.application.environment == .testing {
            var accounts = req.application.storage[MemoryKey.self] ?? []
            guard let idx = accounts.firstIndex(where: { $0.userId == userId }) else {
                throw Abort(.badRequest, reason: "Insufficient points")
            }
            guard accounts[idx].points >= points else {
                throw Abort(.badRequest, reason: "Insufficient points")
            }
            accounts[idx].points -= points
            accounts[idx].tier = tierFor(points: accounts[idx].points)
            req.application.storage[MemoryKey.self] = accounts
            return
        }
        let coll = req.mongoDB[collection]
        guard let doc = try await coll.findOne("userId" == userId) else {
            throw Abort(.badRequest, reason: "Insufficient points")
        }
        var acc = try BSONDecoder().decode(DBLoyalty.self, from: doc)
        guard acc.points >= points else {
            throw Abort(.badRequest, reason: "Insufficient points")
        }
        acc.points -= points
        acc.tier = tierFor(points: acc.points)
        _ = try await coll.updateOne(where: "_id" == acc._id, to: BSONEncoder().encode(acc))
    }
}

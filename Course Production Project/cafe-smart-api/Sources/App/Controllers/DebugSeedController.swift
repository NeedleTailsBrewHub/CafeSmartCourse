//
//  DebugSeedController.swift
//  CafeSmartAPI
//
//  DEBUG-only admin bootstrap for demo café data.
//

import MongoKitten
import Vapor

#if DEBUG
actor DebugSeedController {
    struct SeedResult: Content, BinaryResponseEncodable {
        var seeded: Bool
        var message: String

        func encodeResponse(for request: Request) async throws -> Response {
            try binaryEncodedResponse()
        }
    }

    func seed(req: Request) async throws -> SeedResult {
        let before = try await req.store.listInventory()
        try await DevDataSeed.ensureMongoSeeded(store: req.store, logger: req.logger)
        let after = try await req.store.listInventory()
        if before.isEmpty && !after.isEmpty {
            return SeedResult(seeded: true, message: "Demo café data loaded.")
        }
        return SeedResult(
            seeded: false,
            message: "Store already had data; seed skipped. POST /api/auth/debug/reseed to wipe and reload.")
    }

    /// Destructive: clears catalog/ops demo collections and loads a fresh realistic seed.
    func reseed(req: Request) async throws -> SeedResult {
        try await DevDataSeed.reseedMongo(
            store: req.store,
            database: liveMongoDatabase(for: req),
            logger: req.logger)
        let inventory = try await req.store.listInventory().count
        let menu = try await req.store.listMenu().count
        let tables = try await req.store.listTables().count
        return SeedResult(
            seeded: true,
            message:
                "Reseeded demo café (\(inventory) inventory, \(menu) menu, \(tables) tables). Users kept.")
    }

    private func liveMongoDatabase(for req: Request) -> MongoDatabase? {
        if req.application.environment == .testing { return nil }
        let useTest = (Environment.get("USE_TEST_STORE") ?? "").lowercased()
        if ["true", "1", "yes"].contains(useTest) { return nil }
        return req.application.mongoDB
    }
}
#endif

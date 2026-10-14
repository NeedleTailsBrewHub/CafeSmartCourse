import MongoKitten
import Vapor

/// DEBUG demo café bootstrap for Mongo (and in-memory tests via the same bundle).
enum DevDataSeed {
    /// Load demo data when inventory is empty. No-op if catalog already exists.
    static func ensureMongoSeeded(store: any MongoStore, logger: Logger) async throws {
        let existing = try await store.listInventory()
        guard existing.isEmpty else {
            logger.info("Mongo already has \(existing.count) inventory item(s); skipping SEED_TEST_DATA")
            return
        }
        try await applySeedBundle(store: store, logger: logger)
    }

    /// Wipe demo collections and load a fresh `DemoCafeSeed` dataset.
    /// Optionally clears `team_members` / `time_entries` when a Mongo database is provided.
    static func reseedMongo(
        store: any MongoStore,
        database: MongoDatabase? = nil,
        logger: Logger
    ) async throws {
        logger.warning("SEED_TEST_DATA: purging demo collections for reseed")
        try await store.purgeDemoData()
        if let database {
            _ = try await database["team_members"].deleteAll(where: [:])
            _ = try await database["time_entries"].deleteAll(where: [:])
        }
        try await applySeedBundle(store: store, logger: logger)
    }

    private static func applySeedBundle(store: any MongoStore, logger: Logger) async throws {
        let bundle = DemoCafeSeed.makeBundle()
        for item in bundle.inventory {
            _ = try await store.create(inventoryItem: item)
        }
        for item in bundle.menu {
            _ = try await store.create(menuItem: item)
        }
        for recipe in bundle.recipes {
            _ = try await store.create(recipe: recipe)
        }
        for area in bundle.areas {
            _ = try await store.create(seatingArea: area)
        }
        for table in bundle.tables {
            _ = try await store.create(table: table)
        }
        for reservation in bundle.reservations {
            _ = try await store.create(reservation: reservation)
        }
        for order in bundle.orders {
            _ = try await store.create(order: order)
        }
        _ = try await store.upsertBusinessConfig(bundle.config)
        for group in bundle.tagGroups {
            _ = try await store.createTagGroup(group)
        }
        for tag in bundle.tags {
            _ = try await store.createTag(tag)
        }
        try await AllergenTagMigration.ensureAndMigrate(store: store, logger: logger)

        logger.info(
            "SEED_TEST_DATA: seeded \(bundle.inventory.count) inventory, \(bundle.menu.count) menu, \(bundle.orders.count) orders, \(bundle.tables.count) tables"
        )
    }
}

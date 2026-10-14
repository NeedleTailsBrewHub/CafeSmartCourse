import Vapor

enum DevDataSeed {
    static func ensureMongoSeeded(store: any MongoStore, logger: Logger) async throws {
        let existing = try await store.listInventory()
        guard existing.isEmpty else {
            logger.info("Mongo already has \(existing.count) inventory item(s); skipping SEED_TEST_DATA")
            return
        }

        let bundle = TestableMongoStore.makeSeedBundle()
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
        for order in bundle.orders {
            _ = try await store.create(order: order)
        }
        _ = try await store.upsertBusinessConfig(bundle.config)

        logger.info(
            "SEED_TEST_DATA: seeded Mongo with \(bundle.inventory.count) inventory, \(bundle.menu.count) menu, \(bundle.orders.count) orders"
        )
    }
}

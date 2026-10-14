@preconcurrency import BSON
import Foundation
import Vapor

/// Neighborhood specialty-café demo dataset shared by in-memory + Mongo seeds.
///
/// Figures aim at a ~36-seat US café: kitchen units (g/ml/ea), wholesale-ish costs,
/// real menu mix, and ~3 months of paid history sized for Finance + Demand + ML.
enum DemoCafeSeed {
    struct Bundle: Sendable {
        let users: [User]
        let inventory: [InventoryItem]
        let menu: [MenuItem]
        let recipes: [Recipe]
        let areas: [SeatingArea]
        let tables: [Table]
        let reservations: [Reservation]
        let orders: [Order]
        let config: BusinessConfig
        let tagGroups: [TagGroup]
        let tags: [Tag]
    }

    static func makeBundle() -> Bundle {
        let now = Date()

        let adminId = ObjectId().hexString
        let userId = ObjectId().hexString
        let adminHash: String = (try? Bcrypt.hash("AdminPass123!"))
            ?? "$2b$12$H1Jg3b7xFQwN4k4ZlQp2xOUxJqzq0vWbQe7j8dQ8d2oT6i6vL2U9y"
        let userHash: String = (try? Bcrypt.hash("UserPass123!"))
            ?? "$2b$12$H1Jg3b7xFQwN4k4ZlQp2xOUxJqzq0vWbQe7j8dQ8d2oT6i6vL2U9y"
        let users = [
            User(
                id: adminId,
                email: "admin@cafesmart.test",
                name: "Cafe Admin",
                isAdmin: true,
                venueRole: .admin,
                passwordHash: adminHash,
                symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
                createdAt: now.addingTimeInterval(-86400 * 30)),
            User(
                id: userId,
                email: "jane.doe@cafesmart.test",
                name: "Jane Doe",
                isAdmin: false,
                venueRole: .guest,
                passwordHash: userHash,
                symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
                createdAt: now.addingTimeInterval(-86400 * 14)),
        ]

        // Inventory in kitchen stock units (g / ml / ea / l) with wholesale-ish costs.
        var invBeans = InventoryItem(
            id: ObjectId().hexString,
            sku: "BEANS-ESP-1KG",
            name: "Espresso beans",
            quantity: 8_000, // 8 kg on hand
            reorderThreshold: 2_500,
            unit: "g",
            supplier: "Coastal Roasters",
            storage: .ambient,
            shelfLifeDays: 45,
            leadTimeDays: 5,
            safetyStock: 1_500,
            parLevel: 10_000,
            reorderQuantity: 6_000,
            costPerUnitCents: 2) // ~$20 / kg
        invBeans.leadTimeDays = 5

        var invMilk = InventoryItem(
            id: ObjectId().hexString,
            sku: "DAIRY-MILK-1L",
            name: "Whole milk",
            quantity: 48, // liters
            reorderThreshold: 16,
            unit: "l",
            supplier: "Valley Dairy",
            storage: .refrigerated,
            shelfLifeDays: 10,
            leadTimeDays: 1,
            safetyStock: 12,
            parLevel: 60,
            reorderQuantity: 40,
            costPerUnitCents: 145)

        var invOat = InventoryItem(
            id: ObjectId().hexString,
            sku: "ALT-OAT-1L",
            name: "Oat milk",
            quantity: 24,
            reorderThreshold: 8,
            unit: "l",
            supplier: "Alt Dairy Co",
            storage: .refrigerated,
            shelfLifeDays: 14,
            leadTimeDays: 2,
            safetyStock: 6,
            parLevel: 30,
            reorderQuantity: 20,
            costPerUnitCents: 280)

        var invCroissant = InventoryItem(
            id: ObjectId().hexString,
            sku: "BAKERY-DOUGH-CROIS",
            name: "Butter croissant (parbaked)",
            quantity: 48,
            reorderThreshold: 18,
            unit: "ea",
            supplier: "Morning Bake Supply",
            storage: .frozen,
            shelfLifeDays: 60,
            leadTimeDays: 3,
            safetyStock: 12,
            parLevel: 60,
            reorderQuantity: 48,
            costPerUnitCents: 95)

        var invAlmond = InventoryItem(
            id: ObjectId().hexString,
            sku: "BAKERY-ALMOND-CROIS",
            name: "Almond croissant (parbaked)",
            quantity: 36,
            reorderThreshold: 12,
            unit: "ea",
            supplier: "Morning Bake Supply",
            storage: .frozen,
            shelfLifeDays: 60,
            leadTimeDays: 3,
            safetyStock: 8,
            parLevel: 40,
            reorderQuantity: 36,
            costPerUnitCents: 120)

        var invMuffin = InventoryItem(
            id: ObjectId().hexString,
            sku: "BAKERY-MUFFIN-BB",
            name: "Blueberry muffin",
            quantity: 24,
            reorderThreshold: 8,
            unit: "ea",
            supplier: "Morning Bake Supply",
            storage: .ambient,
            shelfLifeDays: 3,
            leadTimeDays: 1,
            safetyStock: 6,
            parLevel: 30,
            reorderQuantity: 24,
            costPerUnitCents: 85)

        var invBread = InventoryItem(
            id: ObjectId().hexString,
            sku: "BAKERY-SOURDOUGH",
            name: "Sourdough loaf slices",
            quantity: 40,
            reorderThreshold: 12,
            unit: "slice",
            supplier: "City Bakery",
            storage: .ambient,
            shelfLifeDays: 2,
            leadTimeDays: 1,
            safetyStock: 8,
            parLevel: 48,
            reorderQuantity: 40,
            costPerUnitCents: 45)

        var invAvocado = InventoryItem(
            id: ObjectId().hexString,
            sku: "PRODUCE-AVO",
            name: "Avocado",
            quantity: 30,
            reorderThreshold: 10,
            unit: "ea",
            supplier: "Produce Direct",
            storage: .refrigerated,
            shelfLifeDays: 5,
            leadTimeDays: 2,
            safetyStock: 8,
            parLevel: 36,
            reorderQuantity: 24,
            costPerUnitCents: 110)

        var invSugar = InventoryItem(
            id: ObjectId().hexString,
            sku: "SWEET-SUGAR-1KG",
            name: "Cane sugar",
            quantity: 4_000,
            reorderThreshold: 1_000,
            unit: "g",
            supplier: "Sweet Co.",
            storage: .ambient,
            shelfLifeDays: 365,
            leadTimeDays: 7,
            safetyStock: 500,
            parLevel: 5_000,
            reorderQuantity: 5_000,
            costPerUnitCents: 0) // sub-cent; tracked for usage only

        var invCups = InventoryItem(
            id: ObjectId().hexString,
            sku: "PKG-CUP-12",
            name: "12oz hot cups",
            quantity: 800,
            reorderThreshold: 200,
            unit: "ea",
            supplier: "PackRight",
            storage: .ambient,
            leadTimeDays: 5,
            safetyStock: 150,
            parLevel: 1_000,
            reorderQuantity: 1_000,
            costPerUnitCents: 12)

        var invLids = InventoryItem(
            id: ObjectId().hexString,
            sku: "PKG-LID-12",
            name: "12oz lids",
            quantity: 800,
            reorderThreshold: 200,
            unit: "ea",
            supplier: "PackRight",
            storage: .ambient,
            leadTimeDays: 5,
            safetyStock: 150,
            parLevel: 1_000,
            reorderQuantity: 1_000,
            costPerUnitCents: 8)

        let inventory = [
            invBeans, invMilk, invOat, invCroissant, invAlmond, invMuffin,
            invBread, invAvocado, invSugar, invCups, invLids,
        ]

        // Menu — specialty café pricing
        let espressoId = ObjectId().hexString
        var espresso = MenuItem(
            id: espressoId,
            name: "Espresso",
            description: "Double ristretto shot",
            priceCents: 350,
            isAvailable: true,
            category: "Coffee",
            createdAt: now.addingTimeInterval(-86400 * 60))
        espresso.prepSeconds = 45
        espresso.prepStation = "Barista"
        espresso.loyaltyEarnEnabled = true
        espresso.loyaltyRedeemPoints = 100

        let americanoId = ObjectId().hexString
        var americano = MenuItem(
            id: americanoId,
            name: "Americano",
            description: "Espresso with hot water",
            priceCents: 375,
            isAvailable: true,
            category: "Coffee",
            createdAt: now.addingTimeInterval(-86400 * 60))
        americano.prepSeconds = 60
        americano.prepStation = "Barista"
        americano.sizeOptions = [
            .init(name: "Small", priceDeltaCents: 0),
            .init(name: "Medium", priceDeltaCents: 50),
            .init(name: "Large", priceDeltaCents: 100),
        ]

        let cappuccinoId = ObjectId().hexString
        var cappuccino = MenuItem(
            id: cappuccinoId,
            name: "Cappuccino",
            description: "Espresso, steamed milk, foam",
            priceCents: 475,
            isAvailable: true,
            category: "Coffee",
            createdAt: now.addingTimeInterval(-86400 * 55))
        cappuccino.prepSeconds = 150
        cappuccino.prepStation = "Barista"
        cappuccino.allergens = [.milk]
        cappuccino.sizeOptions = [
            .init(name: "Small", priceDeltaCents: 0),
            .init(name: "Medium", priceDeltaCents: 50),
            .init(name: "Large", priceDeltaCents: 100),
        ]

        let latteId = ObjectId().hexString
        var latte = MenuItem(
            id: latteId,
            name: "Cafe Latte",
            description: "Espresso with steamed milk",
            priceCents: 500,
            isAvailable: true,
            category: "Coffee",
            createdAt: now.addingTimeInterval(-86400 * 55))
        latte.prepSeconds = 160
        latte.prepStation = "Barista"
        latte.allergens = [.milk]
        latte.sizeOptions = [
            .init(name: "Small", priceDeltaCents: 0),
            .init(name: "Medium", priceDeltaCents: 50),
            .init(name: "Large", priceDeltaCents: 100),
        ]

        let flatWhiteId = ObjectId().hexString
        var flatWhite = MenuItem(
            id: flatWhiteId,
            name: "Flat White",
            description: "Double ristretto with microfoam",
            priceCents: 500,
            isAvailable: true,
            category: "Coffee",
            createdAt: now.addingTimeInterval(-86400 * 50))
        flatWhite.prepSeconds = 150
        flatWhite.prepStation = "Barista"
        flatWhite.allergens = [.milk]

        let icedLatteId = ObjectId().hexString
        var icedLatte = MenuItem(
            id: icedLatteId,
            name: "Iced Latte",
            description: "Espresso over ice with cold milk",
            priceCents: 550,
            isAvailable: true,
            category: "Coffee",
            createdAt: now.addingTimeInterval(-86400 * 40))
        icedLatte.prepSeconds = 120
        icedLatte.prepStation = "Barista"
        icedLatte.allergens = [.milk]

        let coldBrewId = ObjectId().hexString
        var coldBrew = MenuItem(
            id: coldBrewId,
            name: "Cold Brew",
            description: "18-hour steep, served over ice",
            priceCents: 450,
            isAvailable: true,
            category: "Coffee",
            createdAt: now.addingTimeInterval(-86400 * 40))
        coldBrew.prepSeconds = 45
        coldBrew.prepStation = "Barista"

        let croissantId = ObjectId().hexString
        var croissant = MenuItem(
            id: croissantId,
            name: "Butter Croissant",
            description: "Flaky laminated pastry",
            priceCents: 375,
            isAvailable: true,
            category: "Bakery",
            createdAt: now.addingTimeInterval(-86400 * 45))
        croissant.prepSeconds = 480
        croissant.prepStation = "Bakery"
        croissant.allergens = [.gluten, .milk]

        let almondId = ObjectId().hexString
        var almondCroissant = MenuItem(
            id: almondId,
            name: "Almond Croissant",
            description: "Filled with almond cream",
            priceCents: 450,
            isAvailable: true,
            category: "Bakery",
            createdAt: now.addingTimeInterval(-86400 * 45))
        almondCroissant.prepSeconds = 540
        almondCroissant.prepStation = "Bakery"
        almondCroissant.allergens = [.gluten, .milk, .nuts]

        let muffinId = ObjectId().hexString
        var muffin = MenuItem(
            id: muffinId,
            name: "Blueberry Muffin",
            description: "House muffin with wild blueberries",
            priceCents: 350,
            isAvailable: true,
            category: "Bakery",
            createdAt: now.addingTimeInterval(-86400 * 30))
        muffin.prepSeconds = 30
        muffin.prepStation = "Bakery"
        muffin.allergens = [.gluten, .milk, .eggs]

        let avoToastId = ObjectId().hexString
        var avoToast = MenuItem(
            id: avoToastId,
            name: "Avocado Toast",
            description: "Sourdough, smashed avocado, chili flake",
            priceCents: 950,
            isAvailable: true,
            category: "Food",
            createdAt: now.addingTimeInterval(-86400 * 20))
        avoToast.prepSeconds = 420
        avoToast.prepStation = "Kitchen"
        avoToast.allergens = [.gluten]

        let allergenGroupId = ObjectId().hexString
        let allergenGroup = TagGroup(
            id: allergenGroupId,
            name: "Allergens",
            slug: "allergens",
            sortOrder: 0,
            allowsMultiple: true,
            createdAt: now,
            updatedAt: now)
        var allergenTags: [Tag] = []
        var allergenTagByCase: [Allergen: String] = [:]
        for (idx, allergen) in Allergen.allCases.enumerated() {
            let tid = ObjectId().hexString
            allergenTags.append(
                Tag(
                    id: tid,
                    groupId: allergenGroupId,
                    name: allergen.rawValue.capitalized,
                    slug: allergen.rawValue,
                    sortOrder: idx,
                    createdAt: now,
                    updatedAt: now))
            allergenTagByCase[allergen] = tid
        }
        cappuccino.tagIds = [allergenTagByCase[.milk]!]
        latte.tagIds = [allergenTagByCase[.milk]!]
        flatWhite.tagIds = [allergenTagByCase[.milk]!]
        icedLatte.tagIds = [allergenTagByCase[.milk]!]
        croissant.tagIds = [allergenTagByCase[.gluten]!, allergenTagByCase[.milk]!]
        almondCroissant.tagIds = [
            allergenTagByCase[.gluten]!, allergenTagByCase[.milk]!, allergenTagByCase[.nuts]!,
        ]
        muffin.tagIds = [
            allergenTagByCase[.gluten]!, allergenTagByCase[.milk]!, allergenTagByCase[.eggs]!,
        ]
        avoToast.tagIds = [allergenTagByCase[.gluten]!]

        let menu = [
            espresso, americano, cappuccino, latte, flatWhite, icedLatte, coldBrew,
            croissant, almondCroissant, muffin, avoToast,
        ]

        let recipes = [
            Recipe(
                id: ObjectId().hexString, menuItemId: espressoId,
                components: [
                    .init(sku: invBeans.sku, unitsPerItem: 18, wastageRate: 0.02),
                    .init(sku: invCups.sku, unitsPerItem: 0), // demitasse — no takeaway cup
                ],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: americanoId,
                components: [
                    .init(sku: invBeans.sku, unitsPerItem: 18, wastageRate: 0.02),
                    .init(sku: invCups.sku, unitsPerItem: 1, wastageRate: 0.01),
                    .init(sku: invLids.sku, unitsPerItem: 1, wastageRate: 0.01),
                ],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: cappuccinoId,
                components: [
                    .init(sku: invBeans.sku, unitsPerItem: 18, wastageRate: 0.02),
                    .init(sku: invMilk.sku, unitsPerItem: 0.15, wastageRate: 0.08),
                    .init(sku: invCups.sku, unitsPerItem: 1, wastageRate: 0.01),
                    .init(sku: invLids.sku, unitsPerItem: 1, wastageRate: 0.01),
                ],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: latteId,
                components: [
                    .init(sku: invBeans.sku, unitsPerItem: 18, wastageRate: 0.02),
                    .init(sku: invMilk.sku, unitsPerItem: 0.25, wastageRate: 0.06),
                    .init(sku: invCups.sku, unitsPerItem: 1, wastageRate: 0.01),
                    .init(sku: invLids.sku, unitsPerItem: 1, wastageRate: 0.01),
                ],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: flatWhiteId,
                components: [
                    .init(sku: invBeans.sku, unitsPerItem: 18, wastageRate: 0.02),
                    .init(sku: invMilk.sku, unitsPerItem: 0.16, wastageRate: 0.06),
                    .init(sku: invCups.sku, unitsPerItem: 1, wastageRate: 0.01),
                ],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: icedLatteId,
                components: [
                    .init(sku: invBeans.sku, unitsPerItem: 18, wastageRate: 0.02),
                    .init(sku: invMilk.sku, unitsPerItem: 0.22, wastageRate: 0.04),
                    .init(sku: invCups.sku, unitsPerItem: 1, wastageRate: 0.01),
                    .init(sku: invLids.sku, unitsPerItem: 1, wastageRate: 0.01),
                ],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: coldBrewId,
                components: [
                    .init(sku: invBeans.sku, unitsPerItem: 22, wastageRate: 0.03),
                    .init(sku: invCups.sku, unitsPerItem: 1, wastageRate: 0.01),
                    .init(sku: invLids.sku, unitsPerItem: 1, wastageRate: 0.01),
                ],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: croissantId,
                components: [.init(sku: invCroissant.sku, unitsPerItem: 1, wastageRate: 0.04)],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: almondId,
                components: [.init(sku: invAlmond.sku, unitsPerItem: 1, wastageRate: 0.04)],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: muffinId,
                components: [.init(sku: invMuffin.sku, unitsPerItem: 1, wastageRate: 0.03)],
                createdAt: now),
            Recipe(
                id: ObjectId().hexString, menuItemId: avoToastId,
                components: [
                    .init(sku: invBread.sku, unitsPerItem: 2, wastageRate: 0.05),
                    .init(sku: invAvocado.sku, unitsPerItem: 1, wastageRate: 0.1),
                ],
                createdAt: now),
        ]

        // ~36-seat floor: main dining + patio + bar
        let mainAreaId = ObjectId().hexString
        let patioAreaId = ObjectId().hexString
        let barAreaId = ObjectId().hexString
        let areas = [
            SeatingArea(id: mainAreaId, name: "Main Hall", defaultTurnMinutes: 75, active: true),
            SeatingArea(id: patioAreaId, name: "Patio", defaultTurnMinutes: 90, active: true),
            SeatingArea(id: barAreaId, name: "Bar", defaultTurnMinutes: 45, active: true),
        ]

        var tables: [Table] = []
        let mainLayouts: [(String, Int, Bool)] = [
            ("T1", 2, true), ("T2", 2, false), ("T3", 4, false), ("T4", 4, true),
            ("T5", 4, false), ("T6", 2, false), ("T7", 6, true), ("T8", 4, false),
        ]
        for (name, seats, accessible) in mainLayouts {
            tables.append(
                Table(
                    id: ObjectId().hexString, areaId: mainAreaId, name: name, capacity: seats,
                    accessible: accessible, highTop: false, outside: false, active: true))
        }
        for (name, seats) in [("P1", 2), ("P2", 4), ("P3", 4), ("P4", 2)] {
            tables.append(
                Table(
                    id: ObjectId().hexString, areaId: patioAreaId, name: name, capacity: seats,
                    accessible: name == "P2", highTop: false, outside: true, active: true))
        }
        for name in ["B1", "B2", "B3", "B4"] {
            tables.append(
                Table(
                    id: ObjectId().hexString, areaId: barAreaId, name: name, capacity: 1,
                    accessible: false, highTop: true, outside: false, active: true))
        }

        var res1 = Reservation(
            id: ObjectId().hexString,
            name: "Jane Doe",
            partySize: 2,
            startTime: now.addingTimeInterval(3600),
            phone: "+1-555-111-2222",
            notes: "Window seat")
        res1.durationMinutes = 75
        res1.areaId = mainAreaId
        res1.tableId = tables.first(where: { $0.name == "T1" })?.id
        res1.status = .active
        res1.customerUserId = userId

        var res2 = Reservation(
            id: ObjectId().hexString,
            name: "John Smith",
            partySize: 4,
            startTime: now.addingTimeInterval(7200),
            phone: "+1-555-333-4444",
            notes: "Birthday — quiet corner")
        res2.durationMinutes = 90
        res2.areaId = patioAreaId
        res2.tableId = tables.first(where: { $0.name == "P2" })?.id
        res2.status = .active

        var reservations = [res1, res2]

        let priceByMenuId: [String: Int] = Dictionary(
            uniqueKeysWithValues: menu.map { ($0.id, $0.priceCents) })

        // Live board tickets (unpaid / in progress)
        var liveDineIn = Order(
            id: ObjectId().hexString,
            status: .pending,
            customerName: "Jane Doe",
            customerUserId: userId,
            items: [
                .init(menuItemId: latteId, name: "Cafe Latte", quantity: 2, notes: nil,
                      unitPriceCents: priceByMenuId[latteId]),
                .init(menuItemId: croissantId, name: "Butter Croissant", quantity: 1, notes: nil,
                      unitPriceCents: priceByMenuId[croissantId]),
            ],
            pickupTime: nil,
            createdAt: now.addingTimeInterval(-1200),
            subtotalCents: (priceByMenuId[latteId] ?? 0) * 2 + (priceByMenuId[croissantId] ?? 0),
            totalCents: (priceByMenuId[latteId] ?? 0) * 2 + (priceByMenuId[croissantId] ?? 0),
            paymentStatus: .unpaid)
        liveDineIn.channel = .dineIn
        liveDineIn.serviceType = .barista
        liveDineIn.tableId = tables.first(where: { $0.name == "T1" })?.id
        liveDineIn.guests = 2
        liveDineIn.reservationId = res1.id

        var liveTakeaway = Order(
            id: ObjectId().hexString,
            status: .preparing,
            customerName: "Walk-in",
            items: [
                .init(menuItemId: cappuccinoId, name: "Cappuccino", quantity: 1, notes: "Oat milk",
                      unitPriceCents: (priceByMenuId[cappuccinoId] ?? 0) + 75),
                .init(menuItemId: coldBrewId, name: "Cold Brew", quantity: 1, notes: nil,
                      unitPriceCents: priceByMenuId[coldBrewId]),
            ],
            pickupTime: now.addingTimeInterval(600),
            createdAt: now.addingTimeInterval(-480),
            subtotalCents: (priceByMenuId[cappuccinoId] ?? 0) + 75 + (priceByMenuId[coldBrewId] ?? 0),
            totalCents: (priceByMenuId[cappuccinoId] ?? 0) + 75 + (priceByMenuId[coldBrewId] ?? 0),
            paymentStatus: .unpaid)
        liveTakeaway.channel = .takeaway
        liveTakeaway.serviceType = .barista

        var orders = [liveDineIn, liveTakeaway]

        // History: quieter neighborhood volumes, coffee-heavy mix, always paid.
        let calendar = Calendar(identifier: .gregorian)
        let daysBack: Int = {
            if let raw = Environment.get("DUMMY_DAYS_BACK"), let v = Int(raw), v > 0 { return v }
            return 90
        }()
        let baseMin = Int(Environment.get("DUMMY_BASE_ORDERS_MIN") ?? "") ?? 2
        let baseMax = Int(Environment.get("DUMMY_BASE_ORDERS_MAX") ?? "") ?? 5
        let maxItemsPerOrder = max(1, Int(Environment.get("DUMMY_MAX_ITEMS_PER_ORDER") ?? "") ?? 3)

        // Approximate specialty-café ticket mix (weights).
        let mix: [(String, Double)] = [
            (latteId, 0.22), (cappuccinoId, 0.16), (americanoId, 0.10), (espressoId, 0.08),
            (flatWhiteId, 0.08), (icedLatteId, 0.09), (coldBrewId, 0.07),
            (croissantId, 0.09), (almondId, 0.05), (muffinId, 0.04), (avoToastId, 0.02),
        ]

        let tableIds = tables.map(\.id)
        let areaIds = areas.map(\.id)
        let firstNames = ["Alice", "Bob", "Carol", "Diego", "Elena", "Farah", "Gus", "Hana", "Ivan", "Jules"]

        if let start = calendar.date(byAdding: .day, value: -daysBack, to: now) {
            for d in 0...daysBack {
                guard let dayDate = calendar.date(byAdding: .day, value: d, to: start) else { continue }
                let weekday = calendar.component(.weekday, from: dayDate)
                let weekendBoost = (weekday == 1 || weekday == 7) ? 1.25 : 1.0
                for hour in 7...19 {
                    let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayDate)
                        ?? dayDate
                    let rush: Double = {
                        if (7...9).contains(hour) { return 1.7 }
                        if (11...13).contains(hour) { return 1.45 }
                        if (15...16).contains(hour) { return 1.2 }
                        if (17...18).contains(hour) { return 1.15 }
                        return 0.65
                    }()
                    let base = Int.random(in: baseMin...max(baseMin, baseMax))
                    let ordersThisHour = max(0, Int(Double(base) * weekendBoost * rush))
                    for _ in 0..<ordersThisHour {
                        var itemsList: [OrderItem] = []
                        let itemCount = 1 + Int.random(in: 0...max(0, maxItemsPerOrder - 1))
                        for _ in 0..<itemCount {
                            let mid = pickWeighted(mix)
                            let qty = Int.random(in: 1...2)
                            let price = priceByMenuId[mid] ?? 0
                            let sizeBump: Int = {
                                // ~35% of sized drinks take Medium/Large
                                guard [americanoId, cappuccinoId, latteId, icedLatteId].contains(mid),
                                      Double.random(in: 0...1) < 0.35
                                else { return 0 }
                                return Bool.random() ? 50 : 100
                            }()
                            itemsList.append(
                                OrderItem(
                                    menuItemId: mid,
                                    quantity: qty,
                                    notes: nil,
                                    unitPriceCents: price + sizeBump,
                                    sizeName: sizeBump == 50 ? "Medium" : (sizeBump == 100 ? "Large" : nil)))
                        }
                        let createdAt = hourDate.addingTimeInterval(TimeInterval(Int.random(in: 0...3599)))
                        let subtotal = itemsList.reduce(0) { $0 + ($1.unitPriceCents ?? 0) * $1.quantity }
                        var ord = Order(
                            id: ObjectId().hexString,
                            status: .completed,
                            customerName: firstNames.randomElement(),
                            items: itemsList,
                            pickupTime: nil,
                            createdAt: createdAt,
                            subtotalCents: subtotal,
                            totalCents: subtotal,
                            paymentStatus: .paid,
                            paidAt: createdAt)
                        ord.channel = weightedChannel(hour: hour)
                        ord.serviceType = itemsList.contains(where: {
                            $0.menuItemId == avoToastId || $0.menuItemId == muffinId
                                || $0.menuItemId == croissantId || $0.menuItemId == almondId
                        }) ? (Bool.random() ? .kitchen : .bakery) : .barista
                        if ord.channel == .dineIn {
                            ord.tableId = tableIds.randomElement()
                            ord.guests = [1, 1, 2, 2, 2, 3, 4].randomElement()
                        }
                        orders.append(ord)
                    }

                    if (11...13).contains(hour) || (17...19).contains(hour) {
                        let resCount = Int.random(in: 0...2)
                        for _ in 0..<resCount {
                            let startTime = hourDate.addingTimeInterval(TimeInterval(Int.random(in: 0...1800)))
                            var res = Reservation(
                                id: ObjectId().hexString,
                                name: firstNames.randomElement() ?? "Guest",
                                partySize: [2, 2, 2, 3, 4].randomElement() ?? 2,
                                startTime: startTime,
                                phone: nil,
                                notes: nil)
                            res.durationMinutes = [60, 75, 90].randomElement()
                            res.areaId = areaIds.randomElement()
                            res.tableId = tableIds.randomElement()
                            res.status = startTime < now ? .completed : .active
                            if Bool.random() && Bool.random() {
                                res.customerUserId = userId
                            }
                            reservations.append(res)
                        }
                    }
                }
            }
        }

        let hours: [BusinessHours] = [
            .init(weekday: 1, open: "08:00", close: "17:00"),
            .init(weekday: 2, open: "07:00", close: "19:00"),
            .init(weekday: 3, open: "07:00", close: "19:00"),
            .init(weekday: 4, open: "07:00", close: "19:00"),
            .init(weekday: 5, open: "07:00", close: "19:00"),
            .init(weekday: 6, open: "07:00", close: "20:00"),
            .init(weekday: 7, open: "08:00", close: "18:00"),
        ]
        var config = BusinessConfig(
            id: ObjectId().hexString,
            timezone: "America/Los_Angeles",
            hours: hours,
            seatingCapacity: 36,
            staffing: StaffingRules(
                ordersPerBaristaPerHour: 28,
                ordersPerBakerPerHour: 20,
                guestsPerHostPerHour: 40))
        config.loyaltyEnabled = true
        config.loyaltyEarnPointsPerUnit = 5
        config.reservationBooking = ReservationBookingSettings(
            enabled: true,
            tablesAvailable: 12,
            defaultPartyCapacity: 4,
            slotIntervalMinutes: 30,
            turnMinutes: 75,
            slotStarts: [])

        return Bundle(
            users: users,
            inventory: inventory,
            menu: menu,
            recipes: recipes,
            areas: areas,
            tables: tables,
            reservations: reservations,
            orders: orders,
            config: config,
            tagGroups: [allergenGroup],
            tags: allergenTags)
    }

    private static func pickWeighted(_ items: [(String, Double)]) -> String {
        let total = items.reduce(0.0) { $0 + $1.1 }
        var r = Double.random(in: 0..<total)
        for (id, weight) in items {
            r -= weight
            if r <= 0 { return id }
        }
        return items.last!.0
    }

    private static func weightedChannel(hour: Int) -> Order.OrderChannel {
        let r = Double.random(in: 0...1)
        if (7...9).contains(hour) {
            if r < 0.55 { return .takeaway }
            if r < 0.80 { return .pickup }
            return .dineIn
        }
        if r < 0.45 { return .dineIn }
        if r < 0.75 { return .takeaway }
        if r < 0.92 { return .pickup }
        return .delivery
    }
}

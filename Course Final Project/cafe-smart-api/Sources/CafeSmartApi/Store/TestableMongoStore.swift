//
//  TestableMongoStore.swift
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
@preconcurrency import Crypto
import Foundation
import Vapor

public actor TestableMongoStore: MongoStore {
    public let id = UUID()
    
    // In-memory collections
    private var users: [User] = []
    private var orders: [Order] = []
    private var inventoryItems: [InventoryItem] = []
    private var menuItems: [MenuItem] = []
    private var reservations: [Reservation] = []
    private var recipes: [Recipe] = []
    private var seatingAreas: [SeatingArea] = []
    private var tables: [Table] = []
    private var businessConfig: BusinessConfig? = nil
    private var modelArtifacts: [MLModelArtifact] = []
    private var trainJobs: [TrainJob] = []
    
    // Refresh tokens stored with userId and expiry (no need to decrypt in tests)
    private struct StoredRefresh: Equatable {
        let userId: String
        let expiresAt: Date
        let data: Data
    }
    
    // MARK: - ML Model Artifacts (testing cache)
    
    public func createModelArtifact(_ artifact: MLModelArtifact) async throws {
        modelArtifacts.removeAll { $0._id == artifact._id }
        modelArtifacts.append(artifact)
    }
    
    public func listModelArtifacts() async throws -> [MLModelArtifact] { modelArtifacts }
    
    public func findModelArtifact(by id: String) async throws -> MLModelArtifact? {
        modelArtifacts.first { $0._id == id || $0.id == id }
    }
    
    public func setActiveModel(id: String) async throws {
        guard let target = modelArtifacts.first(where: { $0._id == id || $0.id == id }) else {
            throw Abort(.notFound, reason: "Model artifact not found")
        }
        let kind = target.kind
        modelArtifacts = modelArtifacts.map { item in
            var m = item
            if m.kind == kind { m.active = (m._id == target._id) }
            return m
        }
    }
    
    public func deleteModelArtifact(id: String) async throws {
        if let art = modelArtifacts.first(where: { $0._id == id || $0.id == id }) {
            try? FileManager.default.removeItem(atPath: art.storedAt)
        }
        modelArtifacts.removeAll { $0._id == id || $0.id == id }
    }

    public func upsertTrainJob(_ job: TrainJob) async throws {
        trainJobs.removeAll { $0.id == job.id }
        trainJobs.append(job)
    }

    public func findTrainJob(by id: String) async throws -> TrainJob? {
        trainJobs.first { $0.id == id }
    }

    public func listTrainJobs(limit: Int) async throws -> [TrainJob] {
        Array(trainJobs.sorted { $0.createdAt > $1.createdAt }.prefix(max(1, limit)))
    }

    public func pruneTrainJobs(keepLast: Int, maxAgeDays: Int) async throws {
        _ = maxAgeDays
        let sorted = trainJobs.sorted { $0.createdAt > $1.createdAt }
        trainJobs = Array(sorted.prefix(max(1, keepLast)))
    }
    private var refreshTokens: [StoredRefresh] = []
    
    // MARK: Init
    public init(seedDummyData: Bool = false) {
        var shouldSeed = seedDummyData
        let seedEnv = (
            Environment.get("SEED_TEST_DATA")
            ?? ""
        ).lowercased()
        if seedEnv == "true" {
             shouldSeed = true
             }
        if shouldSeed {
            let bundle = Self.makeDummyData()
            self.users = bundle.users
            self.inventoryItems = bundle.inventory
            self.menuItems = bundle.menu
            self.recipes = bundle.recipes
            self.seatingAreas = bundle.areas
            self.tables = bundle.tables
            self.reservations = bundle.reservations
            self.orders = bundle.orders
            self.businessConfig = bundle.config
        }
    }
    
    // MARK: Users
    public func createUser(_ user: User) async throws {
        users.removeAll { $0.id == user.id }
        users.append(user)
    }
    
    public func listUsers() async throws -> [User] { users }
    
    public func findUser(byId id: String) async throws -> User? {
        users.first { $0.id == id }
    }
    
    public func findUser(by email: String) async throws -> User? {
        users.first { $0.email.lowercased() == email }
    }
    
    public func updateUser(_ user: User) async throws -> User {
        if let idx = users.firstIndex(where: { $0.id == user.id }) {
            users[idx] = user
        } else {
            users.append(user)
        }
        return user
    }
    
    public func updatePassword(user: User) async throws {
        if let idx = users.firstIndex(where: { $0.id == user.id }) { users[idx] = user }
    }
    
    public func deleteUser(id: String) async throws {
        users.removeAll { $0.id == id }
    }
    
    // MARK: Orders
    public func create(order: Order) async throws -> Order {
        orders.removeAll { $0.id == order.id }
        orders.append(order)
        return order
    }
    
    public func listOrders() async throws -> [Order] { orders }
    
    public func findOrder(by id: String) async throws -> Order? { orders.first { $0.id == id } }
    
    public func update(order: Order) async throws -> Order {
        if let idx = orders.firstIndex(where: { $0.id == order.id }) {
            orders[idx] = order
        } else {
            orders.append(order)
        }
        return order
    }
    
    public func deleteOrder(id: String) async throws { orders.removeAll { $0.id == id } }
    
    // MARK: Inventory
    public func create(inventoryItem: InventoryItem) async throws -> InventoryItem {
        inventoryItems.removeAll { $0.id == inventoryItem.id }
        inventoryItems.append(inventoryItem)
        return inventoryItem
    }
    
    public func listInventory() async throws -> [InventoryItem] {
        inventoryItems
    }
    
    public func findInventory(by id: String) async throws -> InventoryItem? {
        inventoryItems.first { $0.id == id }
    }
    
    public func update(inventoryItem: InventoryItem) async throws -> InventoryItem {
        if let idx = inventoryItems.firstIndex(where: { $0.id == inventoryItem.id }) {
            inventoryItems[idx] = inventoryItem
        } else {
            inventoryItems.append(inventoryItem)
        }
        return inventoryItem
    }
    
    public func deleteInventory(id: String) async throws { inventoryItems.removeAll { $0.id == id } }
    
    // MARK: Menu
    public func create(menuItem: MenuItem) async throws -> MenuItem {
        menuItems.removeAll { $0.id == menuItem.id }
        menuItems.append(menuItem)
        return menuItem
    }
    
    public func listMenu() async throws -> [MenuItem] { menuItems }
    
    public func findMenuItem(by id: String) async throws -> MenuItem? {
        menuItems.first { $0.id == id }
    }
    
    public func update(menuItem: MenuItem) async throws -> MenuItem {
        if let idx = menuItems.firstIndex(where: { $0.id == menuItem.id }) {
            menuItems[idx] = menuItem
        } else {
            menuItems.append(menuItem)
        }
        return menuItem
    }
    
    public func deleteMenuItem(id: String) async throws { menuItems.removeAll { $0.id == id } }
    
    // MARK: Reservations
    public func create(reservation: Reservation) async throws -> Reservation {
        reservations.removeAll { $0.id == reservation.id }
        reservations.append(reservation)
        return reservation
    }
    
    public func listReservations() async throws -> [Reservation] { reservations }
    
    public func findReservation(by id: String) async throws -> Reservation? {
        reservations.first { $0.id == id }
    }
    
    public func deleteReservation(id: String) async throws { reservations.removeAll { $0.id == id } }
    
    // MARK: Refresh tokens & cleanup
    public func createRefreshToken(_ token: RefreshToken, symmetricKey: SymmetricKey) async throws
    -> Data
    {
        let data = try BSONEncoder().encode(token).makeData()
        let sealed = try AES.GCM.seal(data, using: symmetricKey)
        guard let combined = sealed.combined else { throw Abort(.badRequest) }
        // Track by userId and expiry for fast lookups in tests
        refreshTokens.append(
            StoredRefresh(userId: token._id, expiresAt: token.expiresAt, data: combined))
        return combined
    }
    
    public func findUser(refreshToken: Data) async throws -> User? {
        if let stored = refreshTokens.first(where: { $0.data == refreshToken }) {
            return try await findUser(byId: stored.userId)
        }
        return nil
    }
    
    public func cleanupExpiredTokens() async throws {
        let now = Date()
        refreshTokens.removeAll { $0.expiresAt < now }
    }
    
    public func cleanupExpiredTokensForUser(_ username: String, symmetricKey: SymmetricKey)
    async throws
    {
        let now = Date()
        refreshTokens.removeAll { $0.userId == username && $0.expiresAt < now }
    }
    
    public func deleteToken(_ id: String, symmetricKey: SymmetricKey) async throws {
        refreshTokens.removeAll { $0.userId == id }
    }
    
    public func removeUserTokens(_ user: User) async throws {
        refreshTokens.removeAll { $0.userId == user.id }
    }
    
    // MARK: Recipes
    public func create(recipe: Recipe) async throws -> Recipe {
        recipes.removeAll { $0.id == recipe.id }
        recipes.append(recipe)
        return recipe
    }
    
    public func listRecipes() async throws -> [Recipe] { recipes }
    
    public func findRecipe(by id: String) async throws -> Recipe? { recipes.first { $0.id == id } }
    
    public func findRecipes(menuItemId: String) async throws -> [Recipe] {
        recipes.filter { $0.menuItemId == menuItemId }
    }
    
    public func update(recipe: Recipe) async throws -> Recipe {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
        } else {
            recipes.append(recipe)
        }
        return recipe
    }
    
    public func deleteRecipe(id: String) async throws { recipes.removeAll { $0.id == id } }
    
    // MARK: Seating Areas
    public func create(seatingArea: SeatingArea) async throws -> SeatingArea {
        seatingAreas.removeAll { $0.id == seatingArea.id }
        seatingAreas.append(seatingArea)
        return seatingArea
    }
    
    public func listSeatingAreas() async throws -> [SeatingArea] { seatingAreas }
    
    public func findSeatingArea(by id: String) async throws -> SeatingArea? {
        seatingAreas.first { $0.id == id }
    }
    
    public func update(seatingArea: SeatingArea) async throws -> SeatingArea {
        if let idx = seatingAreas.firstIndex(where: { $0.id == seatingArea.id }) {
            seatingAreas[idx] = seatingArea
        } else {
            seatingAreas.append(seatingArea)
        }
        return seatingArea
    }
    
    public func deleteSeatingArea(id: String) async throws {
        seatingAreas.removeAll { $0.id == id }
        tables.removeAll { $0.areaId == id }
    }
    
    // MARK: Tables
    public func create(table: Table) async throws -> Table {
        tables.removeAll { $0.id == table.id }
        tables.append(table)
        return table
    }
    
    public func listTables() async throws -> [Table] { tables }
    
    public func findTable(by id: String) async throws -> Table? { tables.first { $0.id == id } }
    
    public func listTables(in areaId: String) async throws -> [Table] { tables.filter { $0.areaId == areaId } }
    
    public func update(table: Table) async throws -> Table {
        if let idx = tables.firstIndex(where: { $0.id == table.id }) {
            tables[idx] = table
        } else {
            tables.append(table)
        }
        return table
    }
    
    public func deleteTable(id: String) async throws { tables.removeAll { $0.id == id } }
    
    // MARK: Business Config
    public func upsertBusinessConfig(_ config: BusinessConfig) async throws -> BusinessConfig {
        businessConfig = config
        return config
    }
    
    public func getBusinessConfig() async throws -> BusinessConfig? {
        businessConfig
    }
    
    // MARK: - Seeding
    struct SeedBundle: Sendable {
        let users: [User]
        let inventory: [InventoryItem]
        let menu: [MenuItem]
        let recipes: [Recipe]
        let areas: [SeatingArea]
        let tables: [Table]
        let reservations: [Reservation]
        let orders: [Order]
        let config: BusinessConfig
    }

    static func makeSeedBundle() -> SeedBundle { makeDummyData() }
    
    private static func makeDummyData() -> SeedBundle {
        let now = Date()
        
        // Users
        let adminId = ObjectId().hexString
        let userId = ObjectId().hexString
        let adminHash: String = (try? Bcrypt.hash("AdminPass123!")) ?? "$2b$12$H1Jg3b7xFQwN4k4ZlQp2xOUxJqzq0vWbQe7j8dQ8d2oT6i6vL2U9y"
        let userHash: String = (try? Bcrypt.hash("UserPass123!")) ?? "$2b$12$H1Jg3b7xFQwN4k4ZlQp2xOUxJqzq0vWbQe7j8dQ8d2oT6i6vL2U9y"
        let admin = User(
            id: adminId,
            email: "admin@cafesmart.test",
            name: "Cafe Admin",
            isAdmin: true,
            passwordHash: adminHash,
            symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            createdAt: now.addingTimeInterval(-86400)
        )
        let regular = User(
            id: userId,
            email: "jane.doe@cafesmart.test",
            name: "Jane Doe",
            isAdmin: false,
            passwordHash: userHash,
            symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            createdAt: now.addingTimeInterval(-43200)
        )
        let users = [admin, regular]
        
        // ENHANCED INVENTORY - More diverse SKUs for better ML training
        var inventoryItems: [InventoryItem] = []
        
        // Coffee ingredients
        var invEspressoBeans = InventoryItem(
            id: ObjectId().hexString, sku: "BEANS-ESP-1KG", name: "Espresso Beans 1kg", 
            quantity: 4, reorderThreshold: 5, unit: "bag", supplier: "Roasters Inc.")
        invEspressoBeans.leadTimeDays = 3
        invEspressoBeans.safetyStock = 2
        invEspressoBeans.parLevel = 8
        inventoryItems.append(invEspressoBeans)
        
        var invDecafBeans = InventoryItem(
            id: ObjectId().hexString, sku: "BEANS-DECAF-1KG", name: "Decaf Beans 1kg", 
            quantity: 2, reorderThreshold: 3, unit: "bag", supplier: "Roasters Inc.")
        invDecafBeans.leadTimeDays = 3
        inventoryItems.append(invDecafBeans)
        
        // Dairy products
        var invWholeMilk = InventoryItem(
            id: ObjectId().hexString, sku: "DAIRY-MILK-WHOLE-1L", name: "Whole Milk 1L", 
            quantity: 60, reorderThreshold: 15, unit: "carton", supplier: "Local Dairy")
        invWholeMilk.storage = .refrigerated
        invWholeMilk.shelfLifeDays = 10
        invWholeMilk.leadTimeDays = 2
        inventoryItems.append(invWholeMilk)
        
        var invOatMilk = InventoryItem(
            id: ObjectId().hexString, sku: "DAIRY-OAT-1L", name: "Oat Milk 1L", 
            quantity: 30, reorderThreshold: 8, unit: "carton", supplier: "Plant Co.")
        invOatMilk.storage = .refrigerated
        invOatMilk.shelfLifeDays = 14
        inventoryItems.append(invOatMilk)
        
        var invCream = InventoryItem(
            id: ObjectId().hexString, sku: "DAIRY-CREAM-500ML", name: "Heavy Cream 500ml", 
            quantity: 20, reorderThreshold: 5, unit: "carton", supplier: "Local Dairy")
        invCream.storage = .refrigerated
        inventoryItems.append(invCream)
        
        // Sweeteners
        let invSugar = InventoryItem(
            id: ObjectId().hexString, sku: "SWEET-SUGAR-1KG", name: "Granulated Sugar 1kg", 
            quantity: 30, reorderThreshold: 5, unit: "bag", supplier: "Sweet Co.")
        inventoryItems.append(invSugar)
        
        let invHoney = InventoryItem(
            id: ObjectId().hexString, sku: "SWEET-HONEY-500G", name: "Local Honey 500g", 
            quantity: 15, reorderThreshold: 3, unit: "jar", supplier: "Bee Farm")
        inventoryItems.append(invHoney)
        
        let invSyrup = InventoryItem(
            id: ObjectId().hexString, sku: "SWEET-VANILLA-SYRUP-1L", name: "Vanilla Syrup 1L", 
            quantity: 8, reorderThreshold: 2, unit: "bottle", supplier: "Flavor Co.")
        inventoryItems.append(invSyrup)
        
        // Bakery items
        let invCroissantDough = InventoryItem(
            id: ObjectId().hexString, sku: "BAKERY-DOUGH-CROIS", name: "Croissant Dough", 
            quantity: 200, reorderThreshold: 50, unit: "unit", supplier: "Bakery Supply")
        inventoryItems.append(invCroissantDough)
        
        let invMuffinMix = InventoryItem(
            id: ObjectId().hexString, sku: "BAKERY-MUFFIN-MIX-2KG", name: "Muffin Mix 2kg", 
            quantity: 25, reorderThreshold: 5, unit: "bag", supplier: "Bakery Supply")
        inventoryItems.append(invMuffinMix)
        
        let invBagelDough = InventoryItem(
            id: ObjectId().hexString, sku: "BAKERY-DOUGH-BAGEL", name: "Bagel Dough", 
            quantity: 150, reorderThreshold: 30, unit: "unit", supplier: "Bakery Supply")
        inventoryItems.append(invBagelDough)
        
        // Additional ingredients
        let invCinnamon = InventoryItem(
            id: ObjectId().hexString, sku: "SPICE-CINNAMON-100G", name: "Cinnamon 100g", 
            quantity: 12, reorderThreshold: 2, unit: "jar", supplier: "Spice Co.")
        inventoryItems.append(invCinnamon)
        
        let invCocoa = InventoryItem(
            id: ObjectId().hexString, sku: "SPICE-COCOA-500G", name: "Cocoa Powder 500g", 
            quantity: 8, reorderThreshold: 2, unit: "bag", supplier: "Chocolate Co.")
        inventoryItems.append(invCocoa)
        
        // ENHANCED MENU - More diverse items for better demand patterns
        var menuItems: [MenuItem] = []
        
        // Coffee drinks
        let espressoId = ObjectId().hexString
        var espresso = MenuItem(
            id: espressoId, name: "Espresso", description: "Rich shot of espresso",
            priceCents: 300, isAvailable: true, category: "Coffee", createdAt: now.addingTimeInterval(-7200)
        )
        espresso.prepSeconds = 60
        espresso.prepStation = "Barista"
        menuItems.append(espresso)
        
        let americanoId = ObjectId().hexString
        var americano = MenuItem(
            id: americanoId, name: "Americano", description: "Espresso with hot water",
            priceCents: 350, isAvailable: true, category: "Coffee", createdAt: now.addingTimeInterval(-7100)
        )
        americano.prepSeconds = 90
        americano.prepStation = "Barista"
        menuItems.append(americano)
        
        let cappuccinoId = ObjectId().hexString
        var cappuccino = MenuItem(
            id: cappuccinoId, name: "Cappuccino", description: "Espresso with steamed milk and foam",
            priceCents: 450, isAvailable: true, category: "Coffee", createdAt: now.addingTimeInterval(-7000)
        )
        cappuccino.prepSeconds = 180
        cappuccino.prepStation = "Barista"
        cappuccino.allergens = [.milk]
        cappuccino.sizeOptions = [
            .init(name: "Small", priceDeltaCents: 0),
            .init(name: "Medium", priceDeltaCents: 50),
            .init(name: "Large", priceDeltaCents: 100),
        ]
        menuItems.append(cappuccino)
        
        let latteId = ObjectId().hexString
        var latte = MenuItem(
            id: latteId, name: "Latte", description: "Espresso with steamed milk",
            priceCents: 500, isAvailable: true, category: "Coffee", createdAt: now.addingTimeInterval(-6900)
        )
        latte.prepSeconds = 200
        latte.prepStation = "Barista"
        latte.allergens = [.milk]
        menuItems.append(latte)
        
        let mochaId = ObjectId().hexString
        var mocha = MenuItem(
            id: mochaId, name: "Mocha", description: "Espresso with chocolate and steamed milk",
            priceCents: 550, isAvailable: true, category: "Coffee", createdAt: now.addingTimeInterval(-6800)
        )
        mocha.prepSeconds = 220
        mocha.prepStation = "Barista"
        mocha.allergens = [.milk]
        menuItems.append(mocha)
        
        // Bakery items
        let croissantId = ObjectId().hexString
        var croissant = MenuItem(
            id: croissantId, name: "Butter Croissant", description: "Flaky French pastry",
            priceCents: 350, isAvailable: true, category: "Bakery", createdAt: now.addingTimeInterval(-6800)
        )
        croissant.prepSeconds = 600
        croissant.prepStation = "Bakery"
        croissant.allergens = [.gluten, .milk]
        menuItems.append(croissant)
        
        let muffinId = ObjectId().hexString
        var muffin = MenuItem(
            id: muffinId, name: "Blueberry Muffin", description: "Fresh baked muffin with blueberries",
            priceCents: 400, isAvailable: true, category: "Bakery", createdAt: now.addingTimeInterval(-6700)
        )
        muffin.prepSeconds = 900
        muffin.prepStation = "Bakery"
        muffin.allergens = [.gluten, .milk]
        menuItems.append(muffin)
        
        let bagelId = ObjectId().hexString
        var bagel = MenuItem(
            id: bagelId, name: "Everything Bagel", description: "Fresh bagel with everything seasoning",
            priceCents: 300, isAvailable: true, category: "Bakery", createdAt: now.addingTimeInterval(-6600)
        )
        bagel.prepSeconds = 480
        bagel.prepStation = "Bakery"
        bagel.allergens = [.gluten]
        menuItems.append(bagel)
        
        // ENHANCED RECIPES - Complete mapping for all menu items
        var recipes: [Recipe] = []
        
        let recipeEspresso = Recipe(
            id: ObjectId().hexString,
            menuItemId: espressoId,
            components: [
                .init(sku: invEspressoBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invSugar.sku, unitsPerItem: 0.001, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeEspresso)
        
        let recipeAmericano = Recipe(
            id: ObjectId().hexString,
            menuItemId: americanoId,
            components: [
                .init(sku: invEspressoBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invSugar.sku, unitsPerItem: 0.002, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeAmericano)
        
        let recipeCappuccino = Recipe(
            id: ObjectId().hexString,
            menuItemId: cappuccinoId,
            components: [
                .init(sku: invEspressoBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invWholeMilk.sku, unitsPerItem: 0.2, wastageRate: 0.05),
                .init(sku: invSugar.sku, unitsPerItem: 0.003, wastageRate: 0.01),
                .init(sku: invCinnamon.sku, unitsPerItem: 0.001, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeCappuccino)
        
        let recipeLatte = Recipe(
            id: ObjectId().hexString,
            menuItemId: latteId,
            components: [
                .init(sku: invEspressoBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invWholeMilk.sku, unitsPerItem: 0.3, wastageRate: 0.05),
                .init(sku: invSugar.sku, unitsPerItem: 0.004, wastageRate: 0.01),
                .init(sku: invHoney.sku, unitsPerItem: 0.002, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeLatte)
        
        let recipeMocha = Recipe(
            id: ObjectId().hexString,
            menuItemId: mochaId,
            components: [
                .init(sku: invEspressoBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invWholeMilk.sku, unitsPerItem: 0.25, wastageRate: 0.05),
                .init(sku: invCocoa.sku, unitsPerItem: 0.01, wastageRate: 0.01),
                .init(sku: invSyrup.sku, unitsPerItem: 0.02, wastageRate: 0.01),
                .init(sku: invSugar.sku, unitsPerItem: 0.005, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeMocha)
        
        let recipeCroissant = Recipe(
            id: ObjectId().hexString,
            menuItemId: croissantId,
            components: [
                .init(sku: invCroissantDough.sku, unitsPerItem: 1.0, wastageRate: 0.03),
                .init(sku: invCinnamon.sku, unitsPerItem: 0.002, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeCroissant)
        
        let recipeMuffin = Recipe(
            id: ObjectId().hexString,
            menuItemId: muffinId,
            components: [
                .init(sku: invMuffinMix.sku, unitsPerItem: 0.1, wastageRate: 0.02),
                .init(sku: invSugar.sku, unitsPerItem: 0.008, wastageRate: 0.01),
                .init(sku: invCinnamon.sku, unitsPerItem: 0.003, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeMuffin)
        
        let recipeBagel = Recipe(
            id: ObjectId().hexString,
            menuItemId: bagelId,
            components: [
                .init(sku: invBagelDough.sku, unitsPerItem: 1.0, wastageRate: 0.02),
                .init(sku: invCinnamon.sku, unitsPerItem: 0.001, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeBagel)
        
        // Add additional recipes to use more SKUs
        let recipeDecafEspresso = Recipe(
            id: ObjectId().hexString,
            menuItemId: espressoId, // Reuse espresso menu item for decaf variant
            components: [
                .init(sku: invDecafBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invSugar.sku, unitsPerItem: 0.001, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeDecafEspresso)
        
        let recipeOatMilkLatte = Recipe(
            id: ObjectId().hexString,
            menuItemId: latteId, // Reuse latte menu item for oat milk variant
            components: [
                .init(sku: invEspressoBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invOatMilk.sku, unitsPerItem: 0.3, wastageRate: 0.05),
                .init(sku: invSugar.sku, unitsPerItem: 0.004, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeOatMilkLatte)
        
        let recipeCreamCappuccino = Recipe(
            id: ObjectId().hexString,
            menuItemId: cappuccinoId, // Reuse cappuccino menu item for cream variant
            components: [
                .init(sku: invEspressoBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invCream.sku, unitsPerItem: 0.15, wastageRate: 0.05),
                .init(sku: invSugar.sku, unitsPerItem: 0.003, wastageRate: 0.01),
            ],
            createdAt: now
        )
        recipes.append(recipeCreamCappuccino)
        
        // ENHANCED SEATING AREAS AND TABLES
        let mainAreaId = ObjectId().hexString
        let patioAreaId = ObjectId().hexString
        let loungeAreaId = ObjectId().hexString
        
        let main = SeatingArea(id: mainAreaId, name: "Main Hall", defaultTurnMinutes: 60, active: true)
        let patio = SeatingArea(id: patioAreaId, name: "Patio", defaultTurnMinutes: 75, active: true)
        let lounge = SeatingArea(id: loungeAreaId, name: "Lounge", defaultTurnMinutes: 90, active: true)
        let areas = [main, patio, lounge]
        
        var tables: [Table] = []
        // Main hall tables
        for i in 1...6 {
            let table = Table(
                id: ObjectId().hexString, areaId: mainAreaId, name: "M\(i)", 
                capacity: i <= 2 ? 2 : 4, accessible: i % 3 == 0, 
                highTop: i % 2 == 0, outside: false, active: true
            )
            tables.append(table)
        }
        
        // Patio tables
        for i in 1...4 {
            let table = Table(
                id: ObjectId().hexString, areaId: patioAreaId, name: "P\(i)", 
                capacity: 4, accessible: i % 2 == 0, 
                highTop: false, outside: true, active: true
            )
            tables.append(table)
        }
        
        // Lounge tables
        for i in 1...3 {
            let table = Table(
                id: ObjectId().hexString, areaId: loungeAreaId, name: "L\(i)", 
                capacity: 6, accessible: true, 
                highTop: false, outside: false, active: true
            )
            tables.append(table)
        }
        
        // Reservations
        let res1Id = ObjectId().hexString
        var res1 = Reservation(
            id: res1Id,
            name: "Jane Doe",
            partySize: 2,
            startTime: now.addingTimeInterval(3600),
            phone: "+1-555-111-2222",
            notes: "Window seat"
        )
        res1.durationMinutes = 90
        res1.areaId = mainAreaId
        res1.tableId = tables[0].id
        res1.status = .active
        
        let res2Id = ObjectId().hexString
        var res2 = Reservation(
            id: res2Id,
            name: "John Smith",
            partySize: 4,
            startTime: now.addingTimeInterval(7200),
            phone: "+1-555-333-4444",
            notes: nil
        )
        res2.durationMinutes = 120
        res2.areaId = patioAreaId
        res2.tableId = tables[2].id
        res2.status = .active
        
        var reservations = [res1, res2]
        
        // Orders (reference menu items and optionally reservation)
        let order1 = Order(
            id: ObjectId().hexString,
            status: .pending,
            customerName: "Jane Doe",
            items: [
                .init(menuItemId: espressoId, quantity: 1, notes: "Ristretto"),
                .init(menuItemId: croissantId, quantity: 2, notes: nil),
            ],
            pickupTime: nil,
            createdAt: now.addingTimeInterval(-1800)
        )
        var order1Extended = order1
        order1Extended.channel = .dineIn
        order1Extended.serviceType = .barista
        order1Extended.tableId = tables[0].id
        order1Extended.guests = 2
        order1Extended.reservationId = res1Id
        
        var order2 = Order(
            id: ObjectId().hexString,
            status: .preparing,
            customerName: "Walk-in",
            items: [
                .init(menuItemId: cappuccinoId, quantity: 2, notes: "Oat milk if available"),
            ],
            pickupTime: now.addingTimeInterval(900),
            createdAt: now.addingTimeInterval(-600)
        )
        order2.channel = .takeaway
        order2.serviceType = .barista
        
        var orders = [order1Extended, order2]

        // ENHANCED HISTORICAL DATA GENERATION
        let calendar = Calendar(identifier: .gregorian)
        let daysBack: Int = {
            if let raw = Environment.get("DUMMY_DAYS_BACK"), let v = Int(raw), v > 0 { return v }
            return 365 // Increased to 1 year for better ML training
        }()
        
        let menuIds = [espressoId, americanoId, cappuccinoId, latteId, mochaId, croissantId, muffinId, bagelId]
        let tableIds = tables.map { $0.id }
        let areaIds = [mainAreaId, patioAreaId, loungeAreaId]
        
        if let start = calendar.date(byAdding: .day, value: -daysBack, to: now) {
            for d in 0...daysBack {
                guard let dayDate = calendar.date(byAdding: .day, value: d, to: start) else { continue }
                let weekday = calendar.component(.weekday, from: dayDate)
                let month = calendar.component(.month, from: dayDate)
                
                // Seasonal and day-of-week patterns
                let baseDemand: Double = {
                    switch weekday {
                    case 1, 7: return 1.3 // Weekends
                    case 2: return 0.8    // Monday blues
                    case 6: return 1.1    // Friday
                    default: return 1.0   // Tuesday-Thursday
                    }
                }()
                
                // Seasonal adjustments
                let seasonalMultiplier: Double = {
                    switch month {
                    case 12, 1, 2: return 1.2  // Winter (hot drinks)
                    case 6, 7, 8: return 0.9  // Summer (cold drinks)
                    case 3, 4, 5: return 1.1  // Spring
                    case 9, 10, 11: return 1.0 // Fall
                    default: return 1.0
                    }
                }()
                
                let baseMin: Int = Int(Environment.get("DUMMY_BASE_ORDERS_MIN") ?? "") ?? 8
                let baseMax: Int = Int(Environment.get("DUMMY_BASE_ORDERS_MAX") ?? "") ?? 20
                let maxItemsPerOrder: Int = max(1, Int(Environment.get("DUMMY_MAX_ITEMS_PER_ORDER") ?? "") ?? 4)
                
                // Generate hourly data
                for hour in 6...21 { // Extended hours 6am-9pm
                    let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayDate) ?? dayDate
                    
                    // Enhanced rush hour patterns
                    let rushMultiplier: Double = {
                        switch hour {
                        case 7...9: return 1.8   // Morning rush
                        case 12...13: return 1.6  // Lunch rush
                        case 17...19: return 1.5  // Evening rush
                        case 6, 21: return 0.6   // Early/late hours
                        default: return 0.9       // Regular hours
                        }
                    }()
                    
                    let baseRandom = Int.random(in: baseMin...baseMax)
                    let ordersThisHour = max(0, Int(Double(baseRandom) * baseDemand * seasonalMultiplier * rushMultiplier))
                    
                    // Generate orders for this hour
                    for _ in 0..<ordersThisHour {
                        let oid = ObjectId().hexString
                        let status: OrderStatus = {
                            let rand = Double.random(in: 0...1)
                            if rand < 0.85 { return .completed }
                            else if rand < 0.95 { return .preparing }
                            else { return .ready }
                        }()
                        
                        var itemsList: [OrderItem] = []
                        let itemCount = 1 + Int.random(in: 0...max(0, maxItemsPerOrder - 1))
                        
                        for _ in 0..<itemCount {
                            let mid = menuIds.randomElement() ?? espressoId
                            let qty = 1 + Int.random(in: 0...3) // Increased quantity range
                            let notes: String? = {
                                if Double.random(in: 0...1) < 0.2 {
                                    return ["Extra hot", "Decaf", "Oat milk", "Extra shot", "No foam"].randomElement()
                                }
                                return nil
                            }()
                            itemsList.append(OrderItem(menuItemId: mid, quantity: qty, notes: notes))
                        }
                        
                        let createdAt = hourDate.addingTimeInterval(TimeInterval(Int.random(in: 0...3599)))
                        
                        var ord = Order(
                            id: oid,
                            status: status,
                            customerName: ["Alice","Bob","Carol","Dave","Erin","Frank","Grace","Henry","Ivy","Jack"].randomElement() ?? "Customer",
                            items: itemsList,
                            pickupTime: status == .completed ? createdAt.addingTimeInterval(TimeInterval(Int.random(in: 60...600))) : nil,
                            createdAt: createdAt
                        )
                        
                        // Enhanced order attributes
                        ord.channel = [.dineIn, .takeaway, .pickup, .delivery].randomElement()
                        ord.serviceType = [.barista, .kitchen, .bakery].randomElement()
                        
                        if ord.channel == .dineIn {
                            ord.tableId = tableIds.randomElement()
                            ord.guests = 1 + Int.random(in: 0...5)
                        }
                        
                        // Note: Order model doesn't have completedAt field
                        
                        orders.append(ord)
                    }
                    
                    // Enhanced reservation generation
                    let reservationHours = [11, 12, 13, 17, 18, 19, 20] // Lunch and dinner windows
                    if reservationHours.contains(hour) {
                        let resCount = Int.random(in: 0...8) // Increased reservation count
                        
                        for _ in 0..<resCount {
                            let rid = ObjectId().hexString
                            let startTime = hourDate.addingTimeInterval(TimeInterval(Int.random(in: 0...1800)))
                            
                            var res = Reservation(
                                id: rid,
                                name: ["Jane","John","Alex","Sam","Taylor","Riley","Morgan","Casey","Jordan","Avery"].randomElement() ?? "Guest",
                                partySize: 2 + Int.random(in: 0...6), // Larger party sizes
                                startTime: startTime,
                                phone: Double.random(in: 0...1) < 0.7 ? "+1-555-\(Int.random(in: 100...999))-\(Int.random(in: 1000...9999))" : nil,
                                notes: Double.random(in: 0...1) < 0.3 ? ["Window seat", "Quiet area", "High chair needed", "Anniversary dinner"].randomElement() : nil
                            )
                            
                            res.durationMinutes = [60, 75, 90, 105, 120, 135].randomElement() ?? 90
                            res.areaId = areaIds.randomElement()
                            res.tableId = tableIds.randomElement()
                            res.status = [.active, .completed].randomElement()
                            
                            reservations.append(res)
                        }
                    }
                }
            }
        }
        
        // Business Config
        let hours: [BusinessHours] = [
            .init(weekday: 1, open: "07:00", close: "19:00"),
            .init(weekday: 2, open: "07:00", close: "19:00"),
            .init(weekday: 3, open: "07:00", close: "19:00"),
            .init(weekday: 4, open: "07:00", close: "19:00"),
            .init(weekday: 5, open: "07:00", close: "21:00"),
            .init(weekday: 6, open: "08:00", close: "21:00"),
            .init(weekday: 7, open: "08:00", close: "17:00"),
        ]
        let staffing = StaffingRules(ordersPerBaristaPerHour: 40, ordersPerBakerPerHour: 25, guestsPerHostPerHour: 60)
        let config = BusinessConfig(
            id: ObjectId().hexString,
            timezone: "America/Los_Angeles",
            hours: hours,
            seatingCapacity: 60,
            staffing: staffing
        )
        
        return SeedBundle(
            users: users,
            inventory: inventoryItems,
            menu: menuItems,
            recipes: recipes,
            areas: areas,
            tables: tables,
            reservations: reservations,
            orders: orders,
            config: config
        )
    }
}

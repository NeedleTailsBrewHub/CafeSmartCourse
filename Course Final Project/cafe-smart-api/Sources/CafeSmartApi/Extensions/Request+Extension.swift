//
//  Request+Extension.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//

import Vapor

extension Request {
    
    
    public var store: any MongoStore {
        application.mongoStore
    }
    
}


public protocol MongoStore: Sendable {
    
    // Users (CRUD)
    func createUser(_ user: User) async throws
    func findUser(by email: String) async throws -> User?
    func listUsers() async throws -> [User]
    func findUser(byId id: String) async throws -> User?
    func updateUser(_ user: User) async throws -> User
    func updatePassword(user: User) async throws
    func deleteUser(id: String) async throws

    // Refresh tokens / posts (for testing parity)
    func createRefreshToken(_ token: RefreshToken, symmetricKey: SymmetricKey) async throws -> Data
    func findUser(refreshToken: Data) async throws -> User?
    func cleanupExpiredTokens() async throws
    func cleanupExpiredTokensForUser(_ username: String, symmetricKey: SymmetricKey) async throws
    func deleteToken(_ id: String, symmetricKey: SymmetricKey) async throws
    func removeUserTokens(_ user: User) async throws
    
    // Orders
    func create(order: Order) async throws -> Order
    func listOrders() async throws -> [Order]
    func findOrder(by id: String) async throws -> Order?
    func update(order: Order) async throws -> Order
    func deleteOrder(id: String) async throws
    
    // Inventory
    func create(inventoryItem: InventoryItem) async throws -> InventoryItem
    func listInventory() async throws -> [InventoryItem]
    func findInventory(by id: String) async throws -> InventoryItem?
    func update(inventoryItem: InventoryItem) async throws -> InventoryItem
    func deleteInventory(id: String) async throws

    // Menu Items
    func create(menuItem: MenuItem) async throws -> MenuItem
    func listMenu() async throws -> [MenuItem]
    func findMenuItem(by id: String) async throws -> MenuItem?
    func update(menuItem: MenuItem) async throws -> MenuItem
    func deleteMenuItem(id: String) async throws
    
    // Recipes
    func create(recipe: Recipe) async throws -> Recipe
    func listRecipes() async throws -> [Recipe]
    func findRecipe(by id: String) async throws -> Recipe?
    func findRecipes(menuItemId: String) async throws -> [Recipe]
    func update(recipe: Recipe) async throws -> Recipe
    func deleteRecipe(id: String) async throws
    
    // Reservations
    func create(reservation: Reservation) async throws -> Reservation
    func listReservations() async throws -> [Reservation]
    func findReservation(by id: String) async throws -> Reservation?
    func deleteReservation(id: String) async throws

    // Seating
    func create(seatingArea: SeatingArea) async throws -> SeatingArea
    func listSeatingAreas() async throws -> [SeatingArea]
    func findSeatingArea(by id: String) async throws -> SeatingArea?
    func update(seatingArea: SeatingArea) async throws -> SeatingArea
    func deleteSeatingArea(id: String) async throws

    func create(table: Table) async throws -> Table
    func listTables() async throws -> [Table]
    func findTable(by id: String) async throws -> Table?
    func listTables(in areaId: String) async throws -> [Table]
    func update(table: Table) async throws -> Table
    func deleteTable(id: String) async throws

    // Business config
    func upsertBusinessConfig(_ config: BusinessConfig) async throws -> BusinessConfig
    func getBusinessConfig() async throws -> BusinessConfig?

    // ML model artifacts
    func createModelArtifact(_ artifact: MLModelArtifact) async throws
    func listModelArtifacts() async throws -> [MLModelArtifact]
    func findModelArtifact(by id: String) async throws -> MLModelArtifact?
    func setActiveModel(id: String) async throws
    func deleteModelArtifact(id: String) async throws

    // ML train jobs (durable audit)
    func upsertTrainJob(_ job: TrainJob) async throws
    func findTrainJob(by id: String) async throws -> TrainJob?
    func listTrainJobs(limit: Int) async throws -> [TrainJob]
    func pruneTrainJobs(keepLast: Int, maxAgeDays: Int) async throws
}

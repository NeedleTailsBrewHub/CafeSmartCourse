//
//  MongoCacheManager.swift
//  CafeSmartApi
//
//  Created by Cole M on 9/2/25.
//


//
//  MongoCacheManager.swift
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
import MongoKitten
import Vapor

public actor MongoCacheManager: MongoStore {
  public enum Errors: Error { case notFound }

  private let db: MongoDatabase
  private let orders = "orders"
  private let inventory = "inventory_items"
  private let menu = "menu_items"
  private let reservations = "reservations"
  private let users = "users"
  private let refresh = "refresh_tokens"
  private let recipesCol = "recipes"
  private let seatingAreasCol = "seating_areas"
  private let tablesCol = "tables"
  private let businessConfigCol = "business_config"
  private let mlModelsCol = "ml_models"
  private let mlTrainJobsCol = "ml_train_jobs"

  public init(db: MongoDatabase) {
    self.db = db
  }

  // Internal wrapper for encrypted refresh tokens
  private struct EncryptedObject: Codable, Sendable {
    let userId: String?
    let refreshToken: Data
  }

  // MARK: Orders
  public func create(order: Order) async throws -> Order {
    try await db[orders].insert(try BSONEncoder().encode(order))
    return order
  }

  public func listOrders() async throws -> [Order] {
    var result: [Order] = []
    for try await doc in db[orders].find() { result.append(try BSONDecoder().decode(Order.self, from: doc)) }
    return result
  }

  public func findOrder(by id: String) async throws -> Order? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[orders].findOne("_id" == oid) { return try BSONDecoder().decode(Order.self, from: doc) }
    return nil
  }

  public func update(order: Order) async throws -> Order {
    guard let oid = ObjectId(order.id) else { throw Errors.notFound }
    _ = try await db[orders].updateOne(where: "_id" == oid, to: try BSONEncoder().encode(order))
    return order
  }

  public func deleteOrder(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[orders].deleteOne(where: "_id" == oid)
  }

  // MARK: Inventory
  public func create(inventoryItem: InventoryItem) async throws -> InventoryItem {
    try await db[inventory].insert(try BSONEncoder().encode(inventoryItem))
    return inventoryItem
  }

  public func listInventory() async throws -> [InventoryItem] {
    var result: [InventoryItem] = []
    for try await doc in db[inventory].find() { result.append(try BSONDecoder().decode(InventoryItem.self, from: doc)) }
    return result
  }

  public func findInventory(by id: String) async throws -> InventoryItem? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[inventory].findOne("_id" == oid) {
      return try BSONDecoder().decode(InventoryItem.self, from: doc)
    }
    return nil
  }

  public func update(inventoryItem: InventoryItem) async throws -> InventoryItem {
    guard let oid = ObjectId(inventoryItem.id) else { throw Errors.notFound }
    _ = try await db[inventory].updateOne(
      where: "_id" == oid, to: try BSONEncoder().encode(inventoryItem))
    return inventoryItem
  }

  public func deleteInventory(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[inventory].deleteOne(where: "_id" == oid)
  }

  // MARK: Menu
  public func create(menuItem: MenuItem) async throws -> MenuItem {
    try await db[menu].insert(try BSONEncoder().encode(menuItem))
    return menuItem
  }

  public func listMenu() async throws -> [MenuItem] {
    var result: [MenuItem] = []
    for try await doc in db[menu].find() { result.append(try BSONDecoder().decode(MenuItem.self, from: doc)) }
    return result
  }

  public func findMenuItem(by id: String) async throws -> MenuItem? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[menu].findOne("_id" == oid) { return try BSONDecoder().decode(MenuItem.self, from: doc) }
    return nil
  }

  public func update(menuItem: MenuItem) async throws -> MenuItem {
    guard let oid = ObjectId(menuItem.id) else { throw Errors.notFound }
    _ = try await db[menu].updateOne(where: "_id" == oid, to: try BSONEncoder().encode(menuItem))
    return menuItem
  }

  public func deleteMenuItem(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[menu].deleteOne(where: "_id" == oid)
  }

  // MARK: Reservations
  public func create(reservation: Reservation) async throws -> Reservation {
    try await db[reservations].insert(try BSONEncoder().encode(reservation))
    return reservation
  }

  public func listReservations() async throws -> [Reservation] {
    var result: [Reservation] = []
    for try await doc in db[reservations].find() { result.append(try BSONDecoder().decode(Reservation.self, from: doc)) }
    return result
  }

  public func findReservation(by id: String) async throws -> Reservation? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[reservations].findOne("_id" == oid) { return try BSONDecoder().decode(Reservation.self, from: doc) }
    return nil
  }

  public func deleteReservation(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[reservations].deleteOne(where: "_id" == oid)
  }

  // MARK: Users
  public func createUser(_ user: User) async throws {
    var doc = try BSONEncoder().encode(user)
    // Align Mongo `_id` with the app user id used in JWTs. Without this, Mongo
    // auto-assigns a different ObjectId and auth lookup by JWT `sub` fails.
    if let oid = ObjectId(user.id) {
      doc["_id"] = oid
    }
    try await db[users].insert(doc)
  }

  public func listUsers() async throws -> [User] {
    var result: [User] = []
    for try await doc in db[users].find() { result.append(try BSONDecoder().decode(User.self, from: doc)) }
    return result
  }

  public func findUser(byId id: String) async throws -> User? {
    // Prefer app `id` field (JWT subject). Also accept `_id` for well-formed docs.
    if let doc = try await db[users].findOne("id" == id) {
      return try BSONDecoder().decode(User.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[users].findOne("_id" == oid) {
      return try BSONDecoder().decode(User.self, from: doc)
    }
    return nil
  }

  public func findUser(by email: String) async throws -> User? {
    if let doc = try await db[users].findOne("email" == email) {
      return try BSONDecoder().decode(User.self, from: doc)
    }
    return nil
  }

  public func updateUser(_ user: User) async throws -> User {
    let encoded = try BSONEncoder().encode(user)
    let matched = try await db[users].updateOne(where: "id" == user.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(user.id) {
      _ = try await db[users].updateOne(where: "_id" == oid, to: encoded)
    }
    return user
  }

  public func updatePassword(user: User) async throws {
    let encoded = try BSONEncoder().encode(user)
    let matched = try await db[users].updateOne(where: "id" == user.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(user.id) {
      _ = try await db[users].updateOne(where: "_id" == oid, to: encoded)
    }
  }

  public func deleteUser(id: String) async throws {
    let deleted = try await db[users].deleteOne(where: "id" == id)
    if deleted.deletes == 0, let oid = ObjectId(id) {
      _ = try await db[users].deleteOne(where: "_id" == oid)
    }
  }

  // MARK: Refresh Tokens
  public func createRefreshToken(_ token: RefreshToken, symmetricKey: SymmetricKey) async throws
    -> Data
  {
    let data = try BSONEncoder().encode(token).makeData()
    let sealed = try AES.GCM.seal(data, using: symmetricKey)
    guard let combined = sealed.combined else { throw Abort(.badRequest) }
    let enc = EncryptedObject(userId: token._id, refreshToken: combined)
    try await db[refresh].insert(try BSONEncoder().encode(enc))
    return combined
  }

  public func findUser(refreshToken: Data) async throws -> User? {
    for try await doc in db[refresh].find() {
      guard let enc = try? BSONDecoder().decode(EncryptedObject.self, from: doc),
        enc.refreshToken == refreshToken
      else { continue }

      if let userId = enc.userId, let user = try await findUser(byId: userId) {
        let key = SymmetricKey(data: user.symmetricKey)
        guard let dec = try? AES.GCM.open(.init(combined: refreshToken), using: key),
          let tok = try? BSONDecoder().decode(RefreshToken.self, from: Document(data: dec)),
          tok._id == user.id,
          tok.expiresAt >= Date()
        else { return nil }
        return user
      }

      for user in try await listUsers() {
        let key = SymmetricKey(data: user.symmetricKey)
        guard let dec = try? AES.GCM.open(.init(combined: refreshToken), using: key),
          let tok = try? BSONDecoder().decode(RefreshToken.self, from: Document(data: dec)),
          tok._id == user.id,
          tok.expiresAt >= Date()
        else { continue }
        return user
      }
    }
    return nil
  }

  public func cleanupExpiredTokens() async throws {}

  public func cleanupExpiredTokensForUser(_ username: String, symmetricKey: SymmetricKey)
    async throws
  {
    var toDelete: [Document] = []
    for try await doc in db[refresh].find() {
      if let enc = try? BSONDecoder().decode(EncryptedObject.self, from: doc),
        let dec = try? AES.GCM.open(.init(combined: enc.refreshToken), using: symmetricKey),
        let tok = try? BSONDecoder().decode(RefreshToken.self, from: Document(data: dec))
      {
        if tok._id == username && tok.expiresAt < Date() { toDelete.append(doc) }
      }
    }
    for d in toDelete { _ = try await db[refresh].deleteOne(where: d) }
  }

  public func deleteToken(_ id: String, symmetricKey: SymmetricKey) async throws {
    var toDelete: [Document] = []
    for try await doc in db[refresh].find() {
      if let enc = try? BSONDecoder().decode(EncryptedObject.self, from: doc),
        let dec = try? AES.GCM.open(.init(combined: enc.refreshToken), using: symmetricKey),
        let tok = try? BSONDecoder().decode(RefreshToken.self, from: Document(data: dec))
      {
        if tok._id == id { toDelete.append(doc) }
      }
    }
    for d in toDelete { _ = try await db[refresh].deleteOne(where: d) }
  }

  public func removeUserTokens(_ user: User) async throws {
    for try await doc in db[refresh].find("userId" == user.id) {
      _ = try await db[refresh].deleteOne(where: doc)
    }
  }

  // MARK: Recipes
  public func create(recipe: Recipe) async throws -> Recipe {
    try await db[recipesCol].insert(try BSONEncoder().encode(recipe))
    return recipe
  }

  public func listRecipes() async throws -> [Recipe] {
    var result: [Recipe] = []
      for try await doc in db[recipesCol].find() {
          result.append(try BSONDecoder().decode(Recipe.self, from: doc))
      }
    return result
  }

  public func findRecipe(by id: String) async throws -> Recipe? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[recipesCol].findOne("_id" == oid) { return try BSONDecoder().decode(Recipe.self, from: doc) }
    return nil
  }

  public func findRecipes(menuItemId: String) async throws -> [Recipe] {
    var result: [Recipe] = []
    for try await doc in db[recipesCol].find(["menuItemId": menuItemId]) { result.append(try BSONDecoder().decode(Recipe.self, from: doc)) }
    return result
  }

  public func update(recipe: Recipe) async throws -> Recipe {
    guard let oid = ObjectId(recipe.id) else { throw Errors.notFound }
    _ = try await db[recipesCol].updateOne(where: "_id" == oid, to: try BSONEncoder().encode(recipe))
    return recipe
  }

  public func deleteRecipe(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[recipesCol].deleteOne(where: "_id" == oid)
  }

  // MARK: Seating Areas
  public func create(seatingArea: SeatingArea) async throws -> SeatingArea {
    try await db[seatingAreasCol].insert(try BSONEncoder().encode(seatingArea))
    return seatingArea
  }

  public func listSeatingAreas() async throws -> [SeatingArea] {
    var result: [SeatingArea] = []
    for try await doc in db[seatingAreasCol].find() { result.append(try BSONDecoder().decode(SeatingArea.self, from: doc)) }
    return result
  }

  public func findSeatingArea(by id: String) async throws -> SeatingArea? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[seatingAreasCol].findOne("_id" == oid) { return try BSONDecoder().decode(SeatingArea.self, from: doc) }
    return nil
  }

  public func update(seatingArea: SeatingArea) async throws -> SeatingArea {
    guard let oid = ObjectId(seatingArea.id) else { throw Errors.notFound }
    _ = try await db[seatingAreasCol].updateOne(where: "_id" == oid, to: try BSONEncoder().encode(seatingArea))
    return seatingArea
  }

  public func deleteSeatingArea(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[seatingAreasCol].deleteOne(where: "_id" == oid)
    // Cascade delete tables in this area
    for try await doc in db[tablesCol].find(["areaId": id]) {
      _ = try await db[tablesCol].deleteOne(where: doc)
    }
  }

  // MARK: Tables
  public func create(table: Table) async throws -> Table {
    try await db[tablesCol].insert(try BSONEncoder().encode(table))
    return table
  }

  public func listTables() async throws -> [Table] {
    var result: [Table] = []
    for try await doc in db[tablesCol].find() { result.append(try BSONDecoder().decode(Table.self, from: doc)) }
    return result
  }

  public func findTable(by id: String) async throws -> Table? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[tablesCol].findOne("_id" == oid) { return try BSONDecoder().decode(Table.self, from: doc) }
    return nil
  }

  public func listTables(in areaId: String) async throws -> [Table] {
    var result: [Table] = []
    for try await doc in db[tablesCol].find(["areaId": areaId]) { result.append(try BSONDecoder().decode(Table.self, from: doc)) }
    return result
  }

  public func update(table: Table) async throws -> Table {
    guard let oid = ObjectId(table.id) else { throw Errors.notFound }
    _ = try await db[tablesCol].updateOne(where: "_id" == oid, to: try BSONEncoder().encode(table))
    return table
  }

  public func deleteTable(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[tablesCol].deleteOne(where: "_id" == oid)
  }

  // MARK: Business Config
  public func upsertBusinessConfig(_ config: BusinessConfig) async throws -> BusinessConfig {
    if let oid = ObjectId(config.id) {
      _ = try await db[businessConfigCol].updateOne(where: "_id" == oid, to: try BSONEncoder().encode(config))
      return config
    } else {
      try await db[businessConfigCol].insert(try BSONEncoder().encode(config))
      return config
    }
  }

  public func getBusinessConfig() async throws -> BusinessConfig? {
    if let doc = try await db[businessConfigCol].findOne() { return try BSONDecoder().decode(BusinessConfig.self, from: doc) }
    return nil
  }

  // MARK: - ML Model Artifacts
  public func createModelArtifact(_ artifact: MLModelArtifact) async throws {
    try await db[mlModelsCol].insert(try BSONEncoder().encode(artifact))
  }

  public func listModelArtifacts() async throws -> [MLModelArtifact] {
    var result: [MLModelArtifact] = []
    for try await doc in db[mlModelsCol].find() {
      if let art = try? BSONDecoder().decode(MLModelArtifact.self, from: doc) {
        result.append(art)
      }
    }
    return result
  }

  public func findModelArtifact(by id: String) async throws -> MLModelArtifact? {
    if let doc = try await db[mlModelsCol].findOne("_id" == id) {
      return try BSONDecoder().decode(MLModelArtifact.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[mlModelsCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(MLModelArtifact.self, from: doc)
    }
    if let doc = try await db[mlModelsCol].findOne("id" == id) {
      return try BSONDecoder().decode(MLModelArtifact.self, from: doc)
    }
    return nil
  }

  public func setActiveModel(id: String) async throws {
    guard let artifact = try await findModelArtifact(by: id) else {
      throw Errors.notFound
    }
    _ = try await db[mlModelsCol].updateMany(
      where: ["kind": artifact.kind.rawValue], to: ["$set": ["active": false]])
    if let oid = ObjectId(artifact._id) {
      _ = try await db[mlModelsCol].updateOne(
        where: "_id" == oid, to: ["$set": ["active": true]])
    }
    _ = try await db[mlModelsCol].updateOne(
      where: "_id" == artifact._id, to: ["$set": ["active": true]])
  }

  public func deleteModelArtifact(id: String) async throws {
    if let art = try await findModelArtifact(by: id) {
      try? FileManager.default.removeItem(atPath: art.storedAt)
    }
    if let oid = ObjectId(id) {
      _ = try await db[mlModelsCol].deleteOne(where: "_id" == oid)
    }
    _ = try await db[mlModelsCol].deleteOne(where: "_id" == id)
  }

  // MARK: - ML Train Jobs
  public func upsertTrainJob(_ job: TrainJob) async throws {
    var doc = try BSONEncoder().encode(job)
    doc["_id"] = job.id
    _ = try await db[mlTrainJobsCol].deleteOne(where: "_id" == job.id)
    try await db[mlTrainJobsCol].insert(doc)
  }

  public func findTrainJob(by id: String) async throws -> TrainJob? {
    if let doc = try await db[mlTrainJobsCol].findOne("_id" == id) {
      return try? BSONDecoder().decode(TrainJob.self, from: doc)
    }
    if let doc = try await db[mlTrainJobsCol].findOne("id" == id) {
      return try? BSONDecoder().decode(TrainJob.self, from: doc)
    }
    return nil
  }

  public func listTrainJobs(limit: Int) async throws -> [TrainJob] {
    var result: [TrainJob] = []
    for try await doc in db[mlTrainJobsCol].find() {
      if let job = try? BSONDecoder().decode(TrainJob.self, from: doc) {
        result.append(job)
      }
    }
    return Array(result.sorted { $0.createdAt > $1.createdAt }.prefix(max(1, limit)))
  }

  public func pruneTrainJobs(keepLast: Int, maxAgeDays: Int) async throws {
    let jobs = try await listTrainJobs(limit: 10_000)
    let cutoff = Date().addingTimeInterval(-Double(max(1, maxAgeDays)) * 86_400)
    let keepNewest = Set(jobs.prefix(max(1, keepLast)).map(\.id))
    for job in jobs {
      let beyondCap = !keepNewest.contains(job.id)
      let tooOld = job.createdAt < cutoff && !keepNewest.contains(job.id)
      if beyondCap || tooOld {
        _ = try await db[mlTrainJobsCol].deleteOne(where: "_id" == job.id)
      }
    }
  }
}

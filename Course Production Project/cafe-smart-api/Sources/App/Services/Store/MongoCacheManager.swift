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
  private let tagGroupsCol = "tag_groups"
  private let tagsCol = "tags"
  private let auditCol = "audit_events"
  private let supportTicketsCol = "support_tickets"
  private let checkoutSessionsCol = "checkout_sessions"
  private let catalogMetaCol = "catalog_meta"

  public init(database: MongoDatabase) {
    self.db = database
  }

  /// `$set` patch by app `id`, falling back to Mongo `_id` when aligned.
  private func setByAppId<T: Encodable>(
    collection: String, appId: String, value: T
  ) async throws {
    var fields = try BSONEncoder().encode(value)
    fields.removeValue(forKey: "_id")
    let patch: Document = ["$set": fields]
    var reply = try await db[collection].updateOne(where: "id" == appId, to: patch)
    if reply.updatableCount == 0, let oid = ObjectId(appId) {
      reply = try await db[collection].updateOne(where: "_id" == oid, to: patch)
    }
    guard reply.updatableCount > 0 else {
      throw Abort(.notFound, reason: "\(collection) \(appId) not found for update")
    }
  }

  public func ensureIndexes() async {
    // Best-effort; ignore failures (e.g. standalone without permissions).
    try? await db[orders].createIndex(
      named: "orders_customer_created",
      keys: ["customerUserId": 1, "createdAt": -1, "id": 1])
    try? await db[orders].createIndex(
      named: "orders_status_created",
      keys: ["status": 1, "createdAt": -1, "id": 1])
    try? await db[orders].createIndex(
      named: "orders_created",
      keys: ["createdAt": -1, "id": 1])

    try? await db[menu].createIndex(
      named: "menu_name",
      keys: ["name": 1, "id": 1])
    try? await db[menu].createIndex(
      named: "menu_available_category_name",
      keys: ["isAvailable": 1, "category": 1, "name": 1, "id": 1])
    try? await db[menu].createIndex(named: "menu_tagIds", keys: ["tagIds": 1])

    try? await db[inventory].createIndex(
      named: "inventory_sku_unique",
      keys: ["sku": 1])
    try? await db[inventory].createIndex(
      named: "inventory_name",
      keys: ["name": 1, "id": 1])
    try? await db[inventory].createIndex(named: "inventory_tagIds", keys: ["tagIds": 1])

    try? await db[reservations].createIndex(
      named: "reservations_customer_start",
      keys: ["customerUserId": 1, "startTime": 1, "id": 1])
    try? await db[reservations].createIndex(
      named: "reservations_status_start",
      keys: ["status": 1, "startTime": 1, "id": 1])
    try? await db[reservations].createIndex(
      named: "reservations_start",
      keys: ["startTime": 1, "id": 1])

    try? await db[tagGroupsCol].createIndex(
      named: "tag_groups_sort",
      keys: ["sortOrder": 1, "id": 1])
    try? await db[tagsCol].createIndex(
      named: "tags_group_sort",
      keys: ["groupId": 1, "sortOrder": 1, "id": 1])
    try? await db[auditCol].createIndex(
      named: "audit_entity_created",
      keys: ["entityType": 1, "entityId": 1, "createdAt": -1])
    try? await db[supportTicketsCol].createIndex(
      named: "support_creator_created",
      keys: ["creatorUserId": 1, "createdAt": -1, "id": 1])
    try? await db[supportTicketsCol].createIndex(
      named: "support_status_created",
      keys: ["status": 1, "createdAt": -1, "id": 1])

    try? await db[checkoutSessionsCol].createIndex(
      named: "checkout_sessions_id",
      keys: ["id": 1])
    var checkoutPI = CreateIndexes.Index(
      named: "checkout_sessions_pi_unique", keys: ["paymentIntentId": 1])
    checkoutPI.unique = true
    checkoutPI.sparse = true
    try? await db[checkoutSessionsCol].createIndexes([checkoutPI])
    var orderPI = CreateIndexes.Index(
      named: "orders_stripe_pi_unique", keys: ["stripePaymentIntentId": 1])
    orderPI.unique = true
    orderPI.sparse = true
    try? await db[orders].createIndexes([orderPI])
  }

  // Internal wrapper for encrypted refresh tokens
  private struct EncryptedObject: Codable, Sendable {
    let userId: String?
    let refreshToken: Data
  }

  // MARK: Orders
  public func create(order: Order) async throws -> Order {
    var doc = try BSONEncoder().encode(order)
    // Align Mongo `_id` with app `id` so status/cancel lookups succeed.
    if let oid = ObjectId(order.id) {
      doc["_id"] = oid
    }
    try await db[orders].insert(doc)
    return order
  }

  public func listOrders() async throws -> [Order] {
    var result: [Order] = []
    for try await doc in db[orders].find() { result.append(try BSONDecoder().decode(Order.self, from: doc)) }
    return result
  }

  public func listOrders(from: Date, to: Date) async throws -> [Order] {
    let query = AndQuery(conditions: [
      "createdAt" >= from,
      "createdAt" < to,
    ]).makeDocument()
    var result: [Order] = []
    for try await doc in db[orders]
      .find(query)
      .sort(["createdAt": -1, "id": -1])
    {
      result.append(try BSONDecoder().decode(Order.self, from: doc))
    }
    return result
  }

  public func pageOrders(filter: OrderListFilter) async throws -> PageResult<Order> {
    // Indexed filter + sort + limit. Text search matches id / customerName via regex
    // (item name search remains best-effort through customerName).
    var conditions: [Document] = []
    if let customerUserId = filter.customerUserId {
      conditions.append("customerUserId" == customerUserId)
    }
    if !filter.statuses.isEmpty {
      if filter.statuses.count == 1 {
        conditions.append("status" == filter.statuses[0].rawValue)
      } else {
        conditions.append(
          OrQuery(conditions: filter.statuses.map { "status" == $0.rawValue }).makeDocument())
      }
    } else if let status = filter.status {
      conditions.append("status" == status.rawValue)
    }
    if let from = filter.from {
      conditions.append("createdAt" >= from)
    }
    if let to = filter.to {
      conditions.append("createdAt" <= to)
    }
    if let q = filter.q {
      let escaped = NSRegularExpression.escapedPattern(for: q)
      let regex: Document = ["$regex": escaped, "$options": "i"]
      conditions.append(
        OrQuery(conditions: [
          ["id": regex],
          ["customerName": regex],
        ]).makeDocument())
    }
    if let cursor = filter.cursor {
      guard let epoch = Double(cursor.t) else {
        throw Abort(.badRequest, reason: "Invalid cursor")
      }
      let cursorDate = Date(timeIntervalSince1970: epoch)
      // Descending (createdAt, id): take rows strictly before the cursor.
      conditions.append(
        (("createdAt" < cursorDate)
          || (("createdAt" == cursorDate) && ("id" < cursor.id))).makeDocument())
    }

    let query = AndQuery(conditions: conditions).makeDocument()
    var items: [Order] = []
    items.reserveCapacity(min(filter.limit + 1, 101))
    for try await doc in db[orders]
      .find(query)
      .sort(["createdAt": -1, "id": -1])
      .limit(filter.limit + 1)
    {
      items.append(try BSONDecoder().decode(Order.self, from: doc))
    }
    let hasMore = items.count > filter.limit
    let pageItems = Array(items.prefix(filter.limit))
    var next: String?
    if hasMore, let last = pageItems.last {
      next = try ListCursor(
        t: StoreListFilters.sortTimestamp(last.createdAt),
        id: last.id
      ).encode()
    }
    return PageResult(
      items: pageItems,
      page: PageInfo(nextCursor: next, hasMore: hasMore, limit: filter.limit))
  }

  public func findOrder(by id: String) async throws -> Order? {
    if let doc = try await db[orders].findOne("id" == id) {
      return try BSONDecoder().decode(Order.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[orders].findOne("_id" == oid) {
      return try BSONDecoder().decode(Order.self, from: doc)
    }
    return nil
  }

  public func update(order: Order) async throws -> Order {
    // Use $set (not full replace). Replacement updates that omit `_id` can fail
    // silently depending on document shape; we must never return success without a match.
    var fields = try BSONEncoder().encode(order)
    fields.removeValue(forKey: "_id")
    let patch: Document = ["$set": fields]

    var reply = try await db[orders].updateOne(where: "id" == order.id, to: patch)
    if reply.updatableCount == 0, let oid = ObjectId(order.id) {
      reply = try await db[orders].updateOne(where: "_id" == oid, to: patch)
    }
    guard reply.updatableCount > 0 else {
      throw Abort(.notFound, reason: "Order \(order.id) not found for update")
    }
    if let fresh = try await findOrder(by: order.id) {
      return fresh
    }
    return order
  }

  public func deleteOrder(id: String) async throws {
    let deleted = try await db[orders].deleteOne(where: "id" == id)
    if deleted.deletes == 0, let oid = ObjectId(id) {
      _ = try await db[orders].deleteOne(where: "_id" == oid)
    }
  }

  // MARK: Inventory
  public func create(inventoryItem: InventoryItem) async throws -> InventoryItem {
    var doc = try BSONEncoder().encode(inventoryItem)
    if let oid = ObjectId(inventoryItem.id) {
      doc["_id"] = oid
    }
    try await db[inventory].insert(doc)
    return inventoryItem
  }

  public func listInventory() async throws -> [InventoryItem] {
    var result: [InventoryItem] = []
    for try await doc in db[inventory].find() { result.append(try BSONDecoder().decode(InventoryItem.self, from: doc)) }
    return result
  }

  public func pageInventory(filter: InventoryListFilter) async throws -> PageResult<InventoryItem> {
    let tags = try await listTags()
    let groupIds = StoreListFilters.groupTagIds(tags: tags, groupId: filter.tagGroupId)
    let filtered = try await listInventory().filter {
      StoreListFilters.matchesInventory($0, filter: filter, groupTagIds: groupIds)
    }
    return try ListPagination.page(
      filtered,
      limit: filter.limit,
      cursor: filter.cursor,
      sortKey: { StoreListFilters.sortName($0.name) },
      id: \.id,
      ascending: true)
  }

  public func findInventory(by id: String) async throws -> InventoryItem? {
    if let doc = try await db[inventory].findOne("id" == id) {
      return try BSONDecoder().decode(InventoryItem.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[inventory].findOne("_id" == oid) {
      return try BSONDecoder().decode(InventoryItem.self, from: doc)
    }
    return nil
  }

  public func update(inventoryItem: InventoryItem) async throws -> InventoryItem {
    try await setByAppId(
      collection: inventory, appId: inventoryItem.id, value: inventoryItem)
    return inventoryItem
  }

  public func deleteInventory(id: String) async throws {
    guard var item = try await findInventory(by: id) else { return }
    item.deletedAt = Date()
    item.updatedAt = item.deletedAt
    _ = try await update(inventoryItem: item)
  }

  public func deductInventory(bySKU requirements: [String: Int]) async throws {
    for (sku, units) in requirements where units > 0 {
      guard var item = try await listInventory().first(where: {
        $0.sku == sku && $0.deletedAt == nil
      }) else {
        throw Abort(.badRequest, reason: "Missing inventory for SKU \(sku)")
      }
      // Conditional write: only succeed when quantity still covers the deduction.
      let previous = item.quantity
      guard previous >= units else {
        throw Abort(
          .conflict,
          reason: "Insufficient stock for \(item.name) (need \(units), have \(previous))")
      }
      item.quantity = previous - units
      item.updatedAt = Date()
      let encoded = try BSONEncoder().encode(item)
      let matched = try await db[inventory].updateOne(
        where: "id" == item.id && "quantity" == previous,
        to: encoded)
      if matched.updatedCount == 0 {
        throw Abort(.conflict, reason: "Inventory changed concurrently for \(item.name)")
      }
    }
  }

  // MARK: Menu
  public func create(menuItem: MenuItem) async throws -> MenuItem {
    var doc = try BSONEncoder().encode(menuItem)
    if let oid = ObjectId(menuItem.id) {
      doc["_id"] = oid
    }
    try await db[menu].insert(doc)
    return menuItem
  }

  public func listMenu() async throws -> [MenuItem] {
    var result: [MenuItem] = []
    for try await doc in db[menu].find() { result.append(try BSONDecoder().decode(MenuItem.self, from: doc)) }
    return result
  }

  public func pageMenu(filter: MenuListFilter) async throws -> PageResult<MenuItem> {
    let tags = try await listTags()
    let groupIds = StoreListFilters.groupTagIds(tags: tags, groupId: filter.tagGroupId)
    let filtered = try await listMenu().filter {
      StoreListFilters.matchesMenu($0, filter: filter, groupTagIds: groupIds)
    }
    return try ListPagination.page(
      filtered,
      limit: filter.limit,
      cursor: filter.cursor,
      sortKey: { StoreListFilters.sortName($0.name) },
      id: \.id,
      ascending: true)
  }

  public func findMenuItem(by id: String) async throws -> MenuItem? {
    if let doc = try await db[menu].findOne("id" == id) {
      return try BSONDecoder().decode(MenuItem.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[menu].findOne("_id" == oid) {
      return try BSONDecoder().decode(MenuItem.self, from: doc)
    }
    return nil
  }

  public func update(menuItem: MenuItem) async throws -> MenuItem {
    let encoded = try BSONEncoder().encode(menuItem)
    let matched = try await db[menu].updateOne(where: "id" == menuItem.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(menuItem.id) {
      _ = try await db[menu].updateOne(where: "_id" == oid, to: encoded)
    }
    return menuItem
  }

  public func deleteMenuItem(id: String) async throws {
    guard var item = try await findMenuItem(by: id) else { return }
    item.deletedAt = Date()
    item.updatedAt = item.deletedAt
    _ = try await update(menuItem: item)
  }

  public func getCatalogMeta() async throws -> CatalogMeta {
    if let doc = try await db[catalogMetaCol].findOne("id" == CatalogMeta.menuId) {
      return try BSONDecoder().decode(CatalogMeta.self, from: doc)
    }
    return CatalogMeta()
  }

  public func bumpCatalogVersion() async throws -> CatalogMeta {
    let now = Date()
    var meta = try await getCatalogMeta()
    meta.id = CatalogMeta.menuId
    meta.version += 1
    meta.updatedAt = now
    var doc = try BSONEncoder().encode(meta)
    doc["_id"] = CatalogMeta.menuId
    _ = try await db[catalogMetaCol].deleteAll(where: "id" == CatalogMeta.menuId)
    try await db[catalogMetaCol].insert(doc)
    return meta
  }

  // MARK: Reservations
  public func create(reservation: Reservation) async throws -> Reservation {
    var doc = try BSONEncoder().encode(reservation)
    if let oid = ObjectId(reservation.id) {
      doc["_id"] = oid
    }
    try await db[reservations].insert(doc)
    return reservation
  }

  public func listReservations() async throws -> [Reservation] {
    var result: [Reservation] = []
    for try await doc in db[reservations].find() { result.append(try BSONDecoder().decode(Reservation.self, from: doc)) }
    return result
  }

  public func listReservations(from: Date, to: Date) async throws -> [Reservation] {
    let query = AndQuery(conditions: [
      "startTime" >= from,
      "startTime" < to,
    ]).makeDocument()
    var result: [Reservation] = []
    for try await doc in db[reservations]
      .find(query)
      .sort(["startTime": -1, "id": -1])
    {
      result.append(try BSONDecoder().decode(Reservation.self, from: doc))
    }
    return result
  }

  public func pageReservations(filter: ReservationListFilter) async throws -> PageResult<Reservation> {
    // Indexed filter + sort + limit (mirrors pageOrders). Avoids full-collection scans
    // used by availability day windows and merchant lists.
    var conditions: [Document] = []
    if let customerUserId = filter.customerUserId {
      conditions.append("customerUserId" == customerUserId)
    }
    if let status = filter.status {
      conditions.append("status" == status.rawValue)
    }
    if let from = filter.from {
      conditions.append("startTime" >= from)
    }
    if let to = filter.to {
      conditions.append("startTime" <= to)
    }
    if let q = filter.q {
      let escaped = NSRegularExpression.escapedPattern(for: q)
      let regex: Document = ["$regex": escaped, "$options": "i"]
      conditions.append(
        OrQuery(conditions: [
          ["name": regex],
          ["phone": regex],
          ["notes": regex],
        ]).makeDocument())
    }
    if let cursor = filter.cursor {
      guard let epoch = Double(cursor.t) else {
        throw Abort(.badRequest, reason: "Invalid cursor")
      }
      let cursorDate = Date(timeIntervalSince1970: epoch)
      // Ascending (startTime, id): take rows strictly after the cursor.
      conditions.append(
        (("startTime" > cursorDate)
          || (("startTime" == cursorDate) && ("id" > cursor.id))).makeDocument())
    }

    let query = AndQuery(conditions: conditions).makeDocument()
    var items: [Reservation] = []
    items.reserveCapacity(min(filter.limit + 1, 501))
    for try await doc in db[reservations]
      .find(query)
      .sort(["startTime": 1, "id": 1])
      .limit(filter.limit + 1)
    {
      items.append(try BSONDecoder().decode(Reservation.self, from: doc))
    }
    let hasMore = items.count > filter.limit
    let pageItems = Array(items.prefix(filter.limit))
    var next: String?
    if hasMore, let last = pageItems.last {
      next = try ListCursor(
        t: StoreListFilters.sortTimestamp(last.startTime),
        id: last.id
      ).encode()
    }
    return PageResult(
      items: pageItems,
      page: PageInfo(nextCursor: next, hasMore: hasMore, limit: filter.limit))
  }

  public func findReservation(by id: String) async throws -> Reservation? {
    if let doc = try await db[reservations].findOne("id" == id) {
      return try BSONDecoder().decode(Reservation.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[reservations].findOne("_id" == oid) {
      return try BSONDecoder().decode(Reservation.self, from: doc)
    }
    return nil
  }

  public func update(reservation: Reservation) async throws -> Reservation {
    let encoded = try BSONEncoder().encode(reservation)
    let matched = try await db[reservations].updateOne(where: "id" == reservation.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(reservation.id) {
      _ = try await db[reservations].updateOne(where: "_id" == oid, to: encoded)
    }
    return reservation
  }

  public func deleteReservation(id: String) async throws {
    let deleted = try await db[reservations].deleteOne(where: "id" == id)
    if deleted.deletes == 0, let oid = ObjectId(id) {
      _ = try await db[reservations].deleteOne(where: "_id" == oid)
    }
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

  public func findUser(byEmail emailLowercased: String) async throws -> User? {
    if let doc = try await db[users].findOne("email" == emailLowercased) {
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

      // Legacy docs without userId: decrypt against each user key.
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

  public func deleteRefreshToken(_ data: Data) async throws {
    for try await doc in db[refresh].find() {
      guard let enc = try? BSONDecoder().decode(EncryptedObject.self, from: doc),
        enc.refreshToken == data
      else { continue }
      _ = try await db[refresh].deleteOne(where: doc)
      return
    }
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
    var doc = try BSONEncoder().encode(recipe)
    if let oid = ObjectId(recipe.id) {
      doc["_id"] = oid
    }
    try await db[recipesCol].insert(doc)
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
    if let doc = try await db[recipesCol].findOne("id" == id) {
      return try BSONDecoder().decode(Recipe.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[recipesCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(Recipe.self, from: doc)
    }
    return nil
  }

  public func findRecipes(menuItemId: String) async throws -> [Recipe] {
    var result: [Recipe] = []
    for try await doc in db[recipesCol].find(["menuItemId": menuItemId]) { result.append(try BSONDecoder().decode(Recipe.self, from: doc)) }
    return result
  }

  public func update(recipe: Recipe) async throws -> Recipe {
    try await setByAppId(collection: recipesCol, appId: recipe.id, value: recipe)
    return recipe
  }

  public func deleteRecipe(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[recipesCol].deleteOne(where: "_id" == oid)
  }

  // MARK: Seating Areas
  public func create(seatingArea: SeatingArea) async throws -> SeatingArea {
    var doc = try BSONEncoder().encode(seatingArea)
    if let oid = ObjectId(seatingArea.id) {
      doc["_id"] = oid
    }
    try await db[seatingAreasCol].insert(doc)
    return seatingArea
  }

  public func listSeatingAreas() async throws -> [SeatingArea] {
    var result: [SeatingArea] = []
    for try await doc in db[seatingAreasCol].find() { result.append(try BSONDecoder().decode(SeatingArea.self, from: doc)) }
    return result
  }

  public func findSeatingArea(by id: String) async throws -> SeatingArea? {
    if let doc = try await db[seatingAreasCol].findOne("id" == id) {
      return try BSONDecoder().decode(SeatingArea.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[seatingAreasCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(SeatingArea.self, from: doc)
    }
    return nil
  }

  public func update(seatingArea: SeatingArea) async throws -> SeatingArea {
    try await setByAppId(
      collection: seatingAreasCol, appId: seatingArea.id, value: seatingArea)
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
    var doc = try BSONEncoder().encode(table)
    if let oid = ObjectId(table.id) {
      doc["_id"] = oid
    }
    try await db[tablesCol].insert(doc)
    return table
  }

  public func listTables() async throws -> [Table] {
    var result: [Table] = []
    for try await doc in db[tablesCol].find() { result.append(try BSONDecoder().decode(Table.self, from: doc)) }
    return result
  }

  public func findTable(by id: String) async throws -> Table? {
    if let doc = try await db[tablesCol].findOne("id" == id) {
      return try BSONDecoder().decode(Table.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[tablesCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(Table.self, from: doc)
    }
    return nil
  }

  public func listTables(in areaId: String) async throws -> [Table] {
    var result: [Table] = []
    for try await doc in db[tablesCol].find(["areaId": areaId]) { result.append(try BSONDecoder().decode(Table.self, from: doc)) }
    return result
  }

  public func update(table: Table) async throws -> Table {
    try await setByAppId(collection: tablesCol, appId: table.id, value: table)
    return table
  }

  public func deleteTable(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[tablesCol].deleteOne(where: "_id" == oid)
  }

  // MARK: Business Config
  /// Singleton document. Previous implementation updated by `_id == ObjectId(config.id)` without
  /// ever setting `_id` on insert, so PUTs often matched 0 docs while still returning success —
  /// Loyalty "Accept payments" then snapped off on reload.
  public func upsertBusinessConfig(_ config: BusinessConfig) async throws -> BusinessConfig {
    var doc = try BSONEncoder().encode(config)
    let oid = ObjectId(config.id) ?? ObjectId()
    doc["_id"] = oid
    doc["id"] = oid.hexString
    // Replace the singleton collection contents so stale docs cannot shadow the write.
    _ = try await db[businessConfigCol].deleteAll(where: [:])
    try await db[businessConfigCol].insert(doc)
    var saved = config
    saved.id = oid.hexString
    return saved
  }

  public func getBusinessConfig() async throws -> BusinessConfig? {
    if let doc = try await db[businessConfigCol].findOne() {
      return try BSONDecoder().decode(BusinessConfig.self, from: doc)
    }
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
    // Legacy documents that stored BSON ObjectId in `_id`
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

  // MARK: Tags + audit

  public func createTagGroup(_ group: TagGroup) async throws -> TagGroup {
    var doc = try BSONEncoder().encode(group)
    if let oid = ObjectId(group.id) { doc["_id"] = oid }
    try await db[tagGroupsCol].insert(doc)
    return group
  }

  public func updateTagGroup(_ group: TagGroup) async throws -> TagGroup {
    let encoded = try BSONEncoder().encode(group)
    let matched = try await db[tagGroupsCol].updateOne(where: "id" == group.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(group.id) {
      _ = try await db[tagGroupsCol].updateOne(where: "_id" == oid, to: encoded)
    }
    return group
  }

  public func findTagGroup(by id: String) async throws -> TagGroup? {
    if let doc = try await db[tagGroupsCol].findOne("id" == id) {
      return try BSONDecoder().decode(TagGroup.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[tagGroupsCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(TagGroup.self, from: doc)
    }
    return nil
  }

  public func listTagGroups() async throws -> [TagGroup] {
    var result: [TagGroup] = []
    for try await doc in db[tagGroupsCol].find() {
      result.append(try BSONDecoder().decode(TagGroup.self, from: doc))
    }
    return result
  }

  public func pageTagGroups(filter: TagGroupListFilter) async throws -> PageResult<TagGroup> {
    let filtered = try await listTagGroups().filter {
      StoreListFilters.matchesTagGroup($0, filter: filter)
    }
    return try ListPagination.page(
      filtered,
      limit: filter.limit,
      cursor: filter.cursor,
      sortKey: { StoreListFilters.sortInt($0.sortOrder) },
      id: \.id,
      ascending: true)
  }

  public func archiveTagGroup(id: String, at: Date) async throws {
    guard var group = try await findTagGroup(by: id) else { throw Errors.notFound }
    group.isArchived = true
    group.updatedAt = at
    _ = try await updateTagGroup(group)
    for var tag in try await listTags() where tag.groupId == id {
      tag.isArchived = true
      tag.updatedAt = at
      _ = try await updateTag(tag)
    }
  }

  public func createTag(_ tag: Tag) async throws -> Tag {
    var doc = try BSONEncoder().encode(tag)
    if let oid = ObjectId(tag.id) { doc["_id"] = oid }
    try await db[tagsCol].insert(doc)
    return tag
  }

  public func updateTag(_ tag: Tag) async throws -> Tag {
    let encoded = try BSONEncoder().encode(tag)
    let matched = try await db[tagsCol].updateOne(where: "id" == tag.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(tag.id) {
      _ = try await db[tagsCol].updateOne(where: "_id" == oid, to: encoded)
    }
    return tag
  }

  public func findTag(by id: String) async throws -> Tag? {
    if let doc = try await db[tagsCol].findOne("id" == id) {
      return try BSONDecoder().decode(Tag.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[tagsCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(Tag.self, from: doc)
    }
    return nil
  }

  public func findTags(by ids: [String]) async throws -> [Tag] {
    let wanted = Set(ids)
    return try await listTags().filter { wanted.contains($0.id) }
  }

  public func listTags() async throws -> [Tag] {
    var result: [Tag] = []
    for try await doc in db[tagsCol].find() {
      result.append(try BSONDecoder().decode(Tag.self, from: doc))
    }
    return result
  }

  public func pageTags(filter: TagListFilter) async throws -> PageResult<Tag> {
    let filtered = try await listTags().filter { StoreListFilters.matchesTag($0, filter: filter) }
    return try ListPagination.page(
      filtered,
      limit: filter.limit,
      cursor: filter.cursor,
      sortKey: { StoreListFilters.sortInt($0.sortOrder) },
      id: \.id,
      ascending: true)
  }

  public func archiveTag(id: String, at: Date) async throws {
    guard var tag = try await findTag(by: id) else { throw Errors.notFound }
    tag.isArchived = true
    tag.updatedAt = at
    _ = try await updateTag(tag)
  }

  public func createAuditEvent(_ event: AuditEvent) async throws {
    var doc = try BSONEncoder().encode(event)
    if let oid = ObjectId(event.id) { doc["_id"] = oid }
    try await db[auditCol].insert(doc)
  }

  public func pageAuditEvents(filter: AuditListFilter) async throws -> PageResult<AuditEvent> {
    var all: [AuditEvent] = []
    for try await doc in db[auditCol].find() {
      all.append(try BSONDecoder().decode(AuditEvent.self, from: doc))
    }
    let filtered = all.filter { StoreListFilters.matchesAudit($0, filter: filter) }
    return try ListPagination.page(
      filtered,
      limit: filter.limit,
      cursor: filter.cursor,
      sortKey: { StoreListFilters.sortTimestamp($0.createdAt) },
      id: \.id,
      ascending: false)
  }

  // MARK: Support tickets
  public func create(supportTicket: SupportTicket) async throws -> SupportTicket {
    var doc = try BSONEncoder().encode(supportTicket)
    if let oid = ObjectId(supportTicket.id) { doc["_id"] = oid }
    try await db[supportTicketsCol].insert(doc)
    return supportTicket
  }

  public func findSupportTicket(by id: String) async throws -> SupportTicket? {
    if let doc = try await db[supportTicketsCol].findOne("id" == id) {
      return try BSONDecoder().decode(SupportTicket.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[supportTicketsCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(SupportTicket.self, from: doc)
    }
    return nil
  }

  public func pageSupportTickets(filter: SupportTicketListFilter) async throws -> PageResult<
    SupportTicket
  > {
    var all: [SupportTicket] = []
    for try await doc in db[supportTicketsCol].find() {
      all.append(try BSONDecoder().decode(SupportTicket.self, from: doc))
    }
    let filtered = all.filter { StoreListFilters.matchesSupportTicket($0, filter: filter) }
    return try ListPagination.page(
      filtered,
      limit: filter.limit,
      cursor: filter.cursor,
      sortKey: { StoreListFilters.sortTimestamp($0.createdAt) },
      id: \.id,
      ascending: false)
  }

  public func update(supportTicket: SupportTicket) async throws -> SupportTicket {
    let encoded = try BSONEncoder().encode(supportTicket)
    let matched = try await db[supportTicketsCol].updateOne(
      where: "id" == supportTicket.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(supportTicket.id) {
      _ = try await db[supportTicketsCol].updateOne(where: "_id" == oid, to: encoded)
    }
    return supportTicket
  }

  public func deleteSupportTicket(id: String) async throws {
    let deleted = try await db[supportTicketsCol].deleteOne(where: "id" == id)
    if deleted.deletes == 0, let oid = ObjectId(id) {
      _ = try await db[supportTicketsCol].deleteOne(where: "_id" == oid)
    }
  }

  // MARK: Checkout sessions

  public func create(checkoutSession: CheckoutSession) async throws -> CheckoutSession {
    var doc = try BSONEncoder().encode(checkoutSession)
    if let oid = ObjectId(checkoutSession.id) { doc["_id"] = oid }
    try await db[checkoutSessionsCol].insert(doc)
    return checkoutSession
  }

  public func findCheckoutSession(by id: String) async throws -> CheckoutSession? {
    if let doc = try await db[checkoutSessionsCol].findOne("id" == id) {
      return try BSONDecoder().decode(CheckoutSession.self, from: doc)
    }
    if let oid = ObjectId(id), let doc = try await db[checkoutSessionsCol].findOne("_id" == oid) {
      return try BSONDecoder().decode(CheckoutSession.self, from: doc)
    }
    return nil
  }

  public func findCheckoutSession(byPaymentIntentId paymentIntentId: String) async throws
    -> CheckoutSession?
  {
    if let doc = try await db[checkoutSessionsCol].findOne("paymentIntentId" == paymentIntentId) {
      return try BSONDecoder().decode(CheckoutSession.self, from: doc)
    }
    return nil
  }

  public func update(checkoutSession: CheckoutSession) async throws -> CheckoutSession {
    let encoded = try BSONEncoder().encode(checkoutSession)
    let matched = try await db[checkoutSessionsCol].updateOne(
      where: "id" == checkoutSession.id, to: encoded)
    if matched.updatedCount == 0, let oid = ObjectId(checkoutSession.id) {
      _ = try await db[checkoutSessionsCol].updateOne(where: "_id" == oid, to: encoded)
    }
    return checkoutSession
  }

  public func claimCheckoutSessionForFulfillment(id: String) async throws -> CheckoutSession? {
    let patch: Document = [
      "$set": ["status": CheckoutSessionStatus.fulfilling.rawValue] as Document
    ]
    let reply = try await db[checkoutSessionsCol].updateOne(
      where: "id" == id && "status" == CheckoutSessionStatus.pending.rawValue,
      to: patch)
    guard reply.updatedCount > 0 else { return nil }
    return try await findCheckoutSession(by: id)
  }

  public func purgeDemoData() async throws {
    let collections = [
      orders, inventory, menu, reservations, recipesCol, seatingAreasCol, tablesCol,
      businessConfigCol, tagGroupsCol, tagsCol, auditCol, supportTicketsCol,
      checkoutSessionsCol, catalogMetaCol,
    ]
    for name in collections {
      _ = try await db[name].deleteAll(where: [:])
    }
  }
}

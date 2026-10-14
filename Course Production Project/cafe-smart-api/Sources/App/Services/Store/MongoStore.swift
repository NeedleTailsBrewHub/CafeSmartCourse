//
//  MongoStore.swift
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
import Foundation
import MongoKitten
import Vapor

public protocol MongoStore: Sendable {
  // Orders
  func create(order: Order) async throws -> Order
  func listOrders() async throws -> [Order]
  /// Indexed range query: `createdAt >= from && createdAt < to` (half-open).
  func listOrders(from: Date, to: Date) async throws -> [Order]
  func pageOrders(filter: OrderListFilter) async throws -> PageResult<Order>
  func findOrder(by id: String) async throws -> Order?
  func update(order: Order) async throws -> Order
  func deleteOrder(id: String) async throws

  // Inventory
  func create(inventoryItem: InventoryItem) async throws -> InventoryItem
  func listInventory() async throws -> [InventoryItem]
  func pageInventory(filter: InventoryListFilter) async throws -> PageResult<InventoryItem>
  func findInventory(by id: String) async throws -> InventoryItem?
  func update(inventoryItem: InventoryItem) async throws -> InventoryItem
  func deleteInventory(id: String) async throws
  /// Atomically deduct units by SKU within the store implementation (fail closed on shortfall).
  func deductInventory(bySKU requirements: [String: Int]) async throws

  // Menu Items
  func create(menuItem: MenuItem) async throws -> MenuItem
  func listMenu() async throws -> [MenuItem]
  func pageMenu(filter: MenuListFilter) async throws -> PageResult<MenuItem>
  func findMenuItem(by id: String) async throws -> MenuItem?
  func update(menuItem: MenuItem) async throws -> MenuItem
  func deleteMenuItem(id: String) async throws

  // Menu catalog version
  func getCatalogMeta() async throws -> CatalogMeta
  func bumpCatalogVersion() async throws -> CatalogMeta

  // Reservations
  func create(reservation: Reservation) async throws -> Reservation
  func listReservations() async throws -> [Reservation]
  /// Indexed range query: `startTime >= from && startTime < to` (half-open).
  func listReservations(from: Date, to: Date) async throws -> [Reservation]
  func pageReservations(filter: ReservationListFilter) async throws -> PageResult<Reservation>
  func findReservation(by id: String) async throws -> Reservation?
  func update(reservation: Reservation) async throws -> Reservation
  func deleteReservation(id: String) async throws

  // Users (CRUD)
  func createUser(_ user: User) async throws
  func listUsers() async throws -> [User]
  func findUser(byId id: String) async throws -> User?
  func findUser(byEmail emailLowercased: String) async throws -> User?
  func updateUser(_ user: User) async throws -> User
  func updatePassword(user: User) async throws
  func deleteUser(id: String) async throws

  // Refresh tokens / posts (for testing parity)
  func createRefreshToken(_ token: RefreshToken, symmetricKey: SymmetricKey) async throws -> Data
  func findUser(refreshToken: Data) async throws -> User?
  func deleteRefreshToken(_ data: Data) async throws
  func cleanupExpiredTokens() async throws
  func cleanupExpiredTokensForUser(_ username: String, symmetricKey: SymmetricKey) async throws
  func deleteToken(_ id: String, symmetricKey: SymmetricKey) async throws
  func removeUserTokens(_ user: User) async throws

  // Recipes
  func create(recipe: Recipe) async throws -> Recipe
  func listRecipes() async throws -> [Recipe]
  func findRecipe(by id: String) async throws -> Recipe?
  func findRecipes(menuItemId: String) async throws -> [Recipe]
  func update(recipe: Recipe) async throws -> Recipe
  func deleteRecipe(id: String) async throws

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

  // Business config (assume singleton)
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

  // Tag taxonomy
  func createTagGroup(_ group: TagGroup) async throws -> TagGroup
  func updateTagGroup(_ group: TagGroup) async throws -> TagGroup
  func findTagGroup(by id: String) async throws -> TagGroup?
  func listTagGroups() async throws -> [TagGroup]
  func pageTagGroups(filter: TagGroupListFilter) async throws -> PageResult<TagGroup>
  func archiveTagGroup(id: String, at: Date) async throws

  func createTag(_ tag: Tag) async throws -> Tag
  func updateTag(_ tag: Tag) async throws -> Tag
  func findTag(by id: String) async throws -> Tag?
  func findTags(by ids: [String]) async throws -> [Tag]
  func listTags() async throws -> [Tag]
  func pageTags(filter: TagListFilter) async throws -> PageResult<Tag>
  func archiveTag(id: String, at: Date) async throws

  // Audit
  func createAuditEvent(_ event: AuditEvent) async throws
  func pageAuditEvents(filter: AuditListFilter) async throws -> PageResult<AuditEvent>

  // Support tickets
  func create(supportTicket: SupportTicket) async throws -> SupportTicket
  func findSupportTicket(by id: String) async throws -> SupportTicket?
  func pageSupportTickets(filter: SupportTicketListFilter) async throws -> PageResult<SupportTicket>
  func update(supportTicket: SupportTicket) async throws -> SupportTicket
  func deleteSupportTicket(id: String) async throws

  // Checkout sessions (prepaid)
  func create(checkoutSession: CheckoutSession) async throws -> CheckoutSession
  func findCheckoutSession(by id: String) async throws -> CheckoutSession?
  func findCheckoutSession(byPaymentIntentId paymentIntentId: String) async throws -> CheckoutSession?
  func update(checkoutSession: CheckoutSession) async throws -> CheckoutSession
  /// Atomically claim `pending` → `fulfilling`. Returns claimed session or nil if lost the race.
  func claimCheckoutSessionForFulfillment(id: String) async throws -> CheckoutSession?

  /// Clears catalog / ops collections used by demo seed (not users, refresh tokens, or ML artifacts).
  func purgeDemoData() async throws
}

// App storage for dependency injection
extension Application {
  private struct MongoStoreKey: StorageKey { typealias Value = any MongoStore }
  public var mongoStore: any MongoStore {
    get {
      if let store = storage[MongoStoreKey.self] { return store }
      // Testing teardown races can clear storage while a request is in flight.
      // Rebind an empty in-memory store instead of crashing the suite process.
      if environment == .testing {
        let fallback = TestableMongoStore(seedDummyData: false)
        storage[MongoStoreKey.self] = fallback
        return fallback
      }
      preconditionFailure("mongoStore not configured — call configure(app) first")
    }
    set { storage[MongoStoreKey.self] = newValue }
  }

  private struct StripeClientKey: StorageKey { typealias Value = any StripeClientPort }
  private struct FakeStripeKey: StorageKey { typealias Value = FakeStripeClient }

  var stripeClient: any StripeClientPort {
    get {
      if let c = storage[StripeClientKey.self] { return c }
      return DisabledStripeClient()
    }
    set { storage[StripeClientKey.self] = newValue }
  }

  var fakeStripe: FakeStripeClient? {
    get { storage[FakeStripeKey.self] }
    set { storage[FakeStripeKey.self] = newValue }
  }
}

/// Used when payments are disabled — any call fails closed.
struct DisabledStripeClient: StripeClientPort {
  func ensureCustomer(userId: String, email: String, existingCustomerId: String?) async throws -> String {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
  func createEphemeralKey(customerId: String) async throws -> String {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
  func createTaxCalculation(
    currency: String,
    amountCents: Int,
    reference: String,
    taxCode: String?,
    address: StripeTaxAddress?,
    customerIP: String?
  ) async throws -> StripeTaxCalculation {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
  func createPaymentIntent(
    amountCents: Int,
    currency: String,
    customerId: String,
    metadata: [String: String],
    taxCalculationId: String?
  ) async throws -> StripePaymentIntentSnapshot {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
  func retrievePaymentIntent(id: String) async throws -> StripePaymentIntentSnapshot {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
  func refundPaymentIntent(id: String) async throws {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
  func cancelPaymentIntent(id: String) async throws {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
  func createTaxTransaction(fromCalculationId calculationId: String, reference: String) async throws {
    throw Abort(.serviceUnavailable, reason: "Stripe disabled")
  }
}

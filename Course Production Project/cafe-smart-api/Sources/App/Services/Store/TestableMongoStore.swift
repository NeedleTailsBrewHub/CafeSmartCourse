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
    private var catalogMeta: CatalogMeta = CatalogMeta()
    private var reservations: [Reservation] = []
    private var recipes: [Recipe] = []
    private var seatingAreas: [SeatingArea] = []
    private var tables: [Table] = []
    private var businessConfig: BusinessConfig? = nil
    private var modelArtifacts: [MLModelArtifact] = []
    private var trainJobs: [TrainJob] = []
    private var tagGroups: [TagGroup] = []
    private var tags: [Tag] = []
    private var auditEvents: [AuditEvent] = []
    private var supportTickets: [SupportTicket] = []
    private var checkoutSessions: [CheckoutSession] = []
    
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
    public init(seedDummyData: Bool? = nil) {
        // Explicit argument wins; otherwise honor DemoModePolicy (DEBUG + SEED_TEST_DATA).
        let shouldSeed = seedDummyData ?? DemoModePolicy.isEnabled
        if shouldSeed {
            let bundle = DemoCafeSeed.makeBundle()
            self.users = bundle.users
            self.inventoryItems = bundle.inventory
            self.menuItems = bundle.menu
            self.recipes = bundle.recipes
            self.seatingAreas = bundle.areas
            self.tables = bundle.tables
            self.reservations = bundle.reservations
            self.orders = bundle.orders
            self.businessConfig = bundle.config
            self.tagGroups = bundle.tagGroups
            self.tags = bundle.tags
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
    
    public func findUser(byEmail emailLowercased: String) async throws -> User? {
        users.first { $0.email.lowercased() == emailLowercased }
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

    public func listOrders(from: Date, to: Date) async throws -> [Order] {
        orders.filter { $0.createdAt >= from && $0.createdAt < to }
    }

    public func pageOrders(filter: OrderListFilter) async throws -> PageResult<Order> {
        let filtered = orders.filter { StoreListFilters.matchesOrder($0, filter: filter) }
        return try ListPagination.page(
            filtered,
            limit: filter.limit,
            cursor: filter.cursor,
            sortKey: { StoreListFilters.sortTimestamp($0.createdAt) },
            id: \.id,
            ascending: false)
    }
    
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

    public func pageInventory(filter: InventoryListFilter) async throws -> PageResult<InventoryItem> {
        let groupIds = StoreListFilters.groupTagIds(tags: tags, groupId: filter.tagGroupId)
        let filtered = inventoryItems.filter {
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
    
    public func deleteInventory(id: String) async throws {
        guard let idx = inventoryItems.firstIndex(where: { $0.id == id }) else { return }
        inventoryItems[idx].deletedAt = Date()
    }

    public func deductInventory(bySKU requirements: [String: Int]) async throws {
        for (sku, units) in requirements where units > 0 {
            guard let idx = inventoryItems.firstIndex(where: {
                $0.sku == sku && $0.deletedAt == nil
            }) else {
                throw Abort(.badRequest, reason: "Missing inventory for SKU \(sku)")
            }
            let have = inventoryItems[idx].quantity
            guard have >= units else {
                throw Abort(
                    .conflict,
                    reason:
                        "Insufficient stock for \(inventoryItems[idx].name) (need \(units), have \(have))"
                )
            }
            inventoryItems[idx].quantity = have - units
            inventoryItems[idx].updatedAt = Date()
        }
    }
    
    // MARK: Menu
    public func create(menuItem: MenuItem) async throws -> MenuItem {
        menuItems.removeAll { $0.id == menuItem.id }
        menuItems.append(menuItem)
        return menuItem
    }
    
    public func listMenu() async throws -> [MenuItem] { menuItems }

    public func pageMenu(filter: MenuListFilter) async throws -> PageResult<MenuItem> {
        let groupIds = StoreListFilters.groupTagIds(tags: tags, groupId: filter.tagGroupId)
        let filtered = menuItems.filter {
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
    
    public func deleteMenuItem(id: String) async throws {
        guard let idx = menuItems.firstIndex(where: { $0.id == id }) else { return }
        menuItems[idx].deletedAt = Date()
    }

    public func getCatalogMeta() async throws -> CatalogMeta { catalogMeta }

    public func bumpCatalogVersion() async throws -> CatalogMeta {
        catalogMeta.version += 1
        catalogMeta.updatedAt = Date()
        return catalogMeta
    }
    
    // MARK: Reservations
    public func create(reservation: Reservation) async throws -> Reservation {
        reservations.removeAll { $0.id == reservation.id }
        reservations.append(reservation)
        return reservation
    }
    
    public func listReservations() async throws -> [Reservation] { reservations }

    public func listReservations(from: Date, to: Date) async throws -> [Reservation] {
        reservations.filter { $0.startTime >= from && $0.startTime < to }
    }

    public func pageReservations(filter: ReservationListFilter) async throws -> PageResult<Reservation> {
        let filtered = reservations.filter { StoreListFilters.matchesReservation($0, filter: filter) }
        return try ListPagination.page(
            filtered,
            limit: filter.limit,
            cursor: filter.cursor,
            sortKey: { StoreListFilters.sortTimestamp($0.startTime) },
            id: \.id,
            ascending: true)
    }
    
    public func findReservation(by id: String) async throws -> Reservation? {
        reservations.first { $0.id == id }
    }

    public func update(reservation: Reservation) async throws -> Reservation {
        guard let idx = reservations.firstIndex(where: { $0.id == reservation.id }) else {
            throw Abort(.notFound)
        }
        reservations[idx] = reservation
        return reservation
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
            guard stored.expiresAt >= Date() else { return nil }
            return try await findUser(byId: stored.userId)
        }
        return nil
    }

    public func deleteRefreshToken(_ data: Data) async throws {
        refreshTokens.removeAll { $0.data == data }
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
    
    public func purgeDemoData() async throws {
        orders = []
        inventoryItems = []
        menuItems = []
        catalogMeta = CatalogMeta()
        reservations = []
        recipes = []
        seatingAreas = []
        tables = []
        businessConfig = nil
        tagGroups = []
        tags = []
        auditEvents = []
        supportTickets = []
        checkoutSessions = []
        // Keep users, refresh tokens, and ML artifacts.
    }
}

// MARK: - Tag taxonomy + audit (TestableMongoStore)

extension TestableMongoStore {
    public func createTagGroup(_ group: TagGroup) async throws -> TagGroup {
        tagGroups.removeAll { $0.id == group.id }
        tagGroups.append(group)
        return group
    }

    public func updateTagGroup(_ group: TagGroup) async throws -> TagGroup {
        if let idx = tagGroups.firstIndex(where: { $0.id == group.id }) {
            tagGroups[idx] = group
        } else {
            tagGroups.append(group)
        }
        return group
    }

    public func findTagGroup(by id: String) async throws -> TagGroup? {
        tagGroups.first { $0.id == id }
    }

    public func listTagGroups() async throws -> [TagGroup] { tagGroups }

    public func pageTagGroups(filter: TagGroupListFilter) async throws -> PageResult<TagGroup> {
        let filtered = tagGroups.filter { StoreListFilters.matchesTagGroup($0, filter: filter) }
        return try ListPagination.page(
            filtered,
            limit: filter.limit,
            cursor: filter.cursor,
            sortKey: { StoreListFilters.sortInt($0.sortOrder) },
            id: \.id,
            ascending: true)
    }

    public func archiveTagGroup(id: String, at: Date) async throws {
        guard let idx = tagGroups.firstIndex(where: { $0.id == id }) else {
            throw Abort(.notFound)
        }
        tagGroups[idx].isArchived = true
        tagGroups[idx].updatedAt = at
        for i in tags.indices where tags[i].groupId == id {
            tags[i].isArchived = true
            tags[i].updatedAt = at
        }
    }

    public func createTag(_ tag: Tag) async throws -> Tag {
        tags.removeAll { $0.id == tag.id }
        tags.append(tag)
        return tag
    }

    public func updateTag(_ tag: Tag) async throws -> Tag {
        if let idx = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[idx] = tag
        } else {
            tags.append(tag)
        }
        return tag
    }

    public func findTag(by id: String) async throws -> Tag? {
        tags.first { $0.id == id }
    }

    public func findTags(by ids: [String]) async throws -> [Tag] {
        let wanted = Set(ids)
        return tags.filter { wanted.contains($0.id) }
    }

    public func listTags() async throws -> [Tag] { tags }

    public func pageTags(filter: TagListFilter) async throws -> PageResult<Tag> {
        let filtered = tags.filter { StoreListFilters.matchesTag($0, filter: filter) }
        return try ListPagination.page(
            filtered,
            limit: filter.limit,
            cursor: filter.cursor,
            sortKey: { StoreListFilters.sortInt($0.sortOrder) },
            id: \.id,
            ascending: true)
    }

    public func archiveTag(id: String, at: Date) async throws {
        guard let idx = tags.firstIndex(where: { $0.id == id }) else {
            throw Abort(.notFound)
        }
        tags[idx].isArchived = true
        tags[idx].updatedAt = at
    }

    public func createAuditEvent(_ event: AuditEvent) async throws {
        auditEvents.append(event)
    }

    public func pageAuditEvents(filter: AuditListFilter) async throws -> PageResult<AuditEvent> {
        let filtered = auditEvents.filter { StoreListFilters.matchesAudit($0, filter: filter) }
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
        supportTickets.removeAll { $0.id == supportTicket.id }
        supportTickets.append(supportTicket)
        return supportTicket
    }

    public func findSupportTicket(by id: String) async throws -> SupportTicket? {
        supportTickets.first { $0.id == id }
    }

    public func pageSupportTickets(filter: SupportTicketListFilter) async throws -> PageResult<SupportTicket> {
        let filtered = supportTickets.filter {
            StoreListFilters.matchesSupportTicket($0, filter: filter)
        }
        return try ListPagination.page(
            filtered,
            limit: filter.limit,
            cursor: filter.cursor,
            sortKey: { StoreListFilters.sortTimestamp($0.createdAt) },
            id: \.id,
            ascending: false)
    }

    public func update(supportTicket: SupportTicket) async throws -> SupportTicket {
        if let idx = supportTickets.firstIndex(where: { $0.id == supportTicket.id }) {
            supportTickets[idx] = supportTicket
        } else {
            supportTickets.append(supportTicket)
        }
        return supportTicket
    }

    public func deleteSupportTicket(id: String) async throws {
        supportTickets.removeAll { $0.id == id }
    }

    // MARK: Checkout sessions

    public func create(checkoutSession: CheckoutSession) async throws -> CheckoutSession {
        checkoutSessions.removeAll { $0.id == checkoutSession.id }
        checkoutSessions.append(checkoutSession)
        return checkoutSession
    }

    public func findCheckoutSession(by id: String) async throws -> CheckoutSession? {
        checkoutSessions.first { $0.id == id }
    }

    public func findCheckoutSession(byPaymentIntentId paymentIntentId: String) async throws
        -> CheckoutSession?
    {
        checkoutSessions.first { $0.paymentIntentId == paymentIntentId }
    }

    public func update(checkoutSession: CheckoutSession) async throws -> CheckoutSession {
        if let idx = checkoutSessions.firstIndex(where: { $0.id == checkoutSession.id }) {
            checkoutSessions[idx] = checkoutSession
        } else {
            checkoutSessions.append(checkoutSession)
        }
        return checkoutSession
    }

    public func claimCheckoutSessionForFulfillment(id: String) async throws -> CheckoutSession? {
        guard let idx = checkoutSessions.firstIndex(where: { $0.id == id }),
            checkoutSessions[idx].status == .pending
        else { return nil }
        checkoutSessions[idx].status = .fulfilling
        return checkoutSessions[idx]
    }
}

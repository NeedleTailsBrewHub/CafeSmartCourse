//
//  routes.swift
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

import MongoKitten
import Vapor

func routes(_ app: Application) throws {
    // Base API group
    let api = app.grouped("api")
    let auth = api.grouped("auth")
    
    // Controllers
    let userController = UserController()
    let menuController = MenuController()
    let orderController = OrderController()
    let reservationController = ReservationController()
    let inventoryController = InventoryController()
    let loyaltyController = LoyaltyController()
    let teamController = TeamController()
    let predictorController = CafePredictorController()
    let reportsController = ReportsController(team: teamController, predictor: predictorController)
    let recipeController = RecipeController()
    let seatingController = SeatingController()
    let configController = ConfigController()
    let tagController = TagController()
    let auditController = AuditController()
    let supportTicketController = SupportTicketController()
    let checkoutController = CheckoutController()
    
    let authPublic = api.grouped(AuthRateLimitMiddleware())
    authPublic.post("register", use: userController.register(req:))
    authPublic.post("login", use: userController.login(req:))
    authPublic.post("auth", "refresh", use: userController.refreshToken(req:))
    
    // Authenticated user actions
    let tokenProtected = auth.grouped(AuthenticationMiddleware())
    tokenProtected.get("me", use: userController.me(req:))
    tokenProtected.post("logout", use: userController.logout(req:))
    tokenProtected.put("profile", use: userController.updateProfile(req:))
    tokenProtected.put("update-password", use: userController.updatePassword(req:))
    tokenProtected.delete("account", use: userController.deleteAccount(req:))
    tokenProtected.get("runtime", use: configController.runtime(req:))

    // Role tiers (minimum role)
    let staffProtected = tokenProtected.grouped(VenueRoleMiddleware(minimum: .staff))
    let managerProtected = tokenProtected.grouped(VenueRoleMiddleware(minimum: .manager))
    let adminProtected = tokenProtected.grouped(AdminMiddleware())
    
    // Menu — reads for all auth (make-info / guest browse); writes manager+
    tokenProtected.get("menu", use: menuController.list(req:))
    tokenProtected.get("menu", "catalog-version", use: menuController.catalogVersion(req:))
    managerProtected.post("menu", "bulk", use: menuController.bulk(req:))
    managerProtected.get("menu", "export", use: menuController.exportCSV(req:))
    managerProtected.post("menu", "import", use: menuController.importCSV(req:))
    managerProtected.post("menu", use: menuController.create(req:))
    tokenProtected.get("menu", ":id", use: menuController.get(req:))
    managerProtected.put("menu", ":id", use: menuController.update(req:))
    managerProtected.delete("menu", ":id", use: menuController.delete(req:))
    managerProtected.on(
      .POST, "menu", ":id", "image",
      body: .collect(maxSize: "5mb"),
      use: menuController.uploadImage(req:))
    managerProtected.delete("menu", ":id", "image", use: menuController.clearImage(req:))

    // Orders (paginated; status: merchant floor any transition; customer cancel-own-pending)
    tokenProtected.get("orders", use: orderController.list(req:))
    tokenProtected.post("orders", use: orderController.create(req:))
    tokenProtected.get("orders", ":id", use: orderController.get(req:))
    tokenProtected.put("orders", ":id", "status", use: orderController.updateStatus(req:))
    managerProtected.delete("orders", ":id", use: orderController.delete(req:))

    // Prepaid checkout (Stripe PaymentSheet) — gated by PaymentsPolicy
    tokenProtected.get("checkout", "capabilities", use: checkoutController.capabilities(req:))
    tokenProtected.post("checkout", "prepare", use: checkoutController.prepare(req:))
    tokenProtected.post("checkout", "confirm", use: checkoutController.confirm(req:))
    // Public webhook (signature verified)
    api.on(.POST, "webhooks", "stripe", body: .collect(maxSize: "1mb"), use: checkoutController.webhook(req:))

    // Reservations (paginated; cancel: owner or floor; hard delete: manager+)
    tokenProtected.get("reservations", "availability", use: reservationController.availability(req:))
    tokenProtected.get("reservations", use: reservationController.list(req:))
    tokenProtected.post("reservations", use: reservationController.create(req:))
    tokenProtected.get("reservations", ":id", use: reservationController.get(req:))
    tokenProtected.put("reservations", ":id", "cancel", use: reservationController.cancel(req:))
    managerProtected.delete("reservations", ":id", use: reservationController.delete(req:))

    // Inventory — manager+
    managerProtected.get("inventory", use: inventoryController.list(req:))
    managerProtected.post("inventory", "bulk", use: inventoryController.bulk(req:))
    managerProtected.get("inventory", "export", use: inventoryController.exportCSV(req:))
    managerProtected.post("inventory", "import", use: inventoryController.importCSV(req:))
    managerProtected.post("inventory", use: inventoryController.create(req:))
    managerProtected.get("inventory", ":id", use: inventoryController.get(req:))
    managerProtected.put("inventory", ":id", use: inventoryController.update(req:))
    managerProtected.delete("inventory", ":id", use: inventoryController.delete(req:))

    // Tag taxonomy — reads auth; writes manager+
    tokenProtected.get("tag-groups", use: tagController.listGroups(req:))
    managerProtected.post("tag-groups", use: tagController.createGroup(req:))
    managerProtected.put("tag-groups", ":id", use: tagController.updateGroup(req:))
    managerProtected.delete("tag-groups", ":id", use: tagController.archiveGroup(req:))
    tokenProtected.get("tag-groups", ":id", "tags", use: tagController.listTagsInGroup(req:))
    tokenProtected.get("tags", use: tagController.listTags(req:))
    managerProtected.post("tags", use: tagController.createTag(req:))
    managerProtected.put("tags", ":id", use: tagController.updateTag(req:))
    managerProtected.delete("tags", ":id", use: tagController.archiveTag(req:))

    // Audit — admin
    adminProtected.get("audit", use: auditController.list(req:))

    // Support tickets — customers create/list own; floor manages desk
    tokenProtected.get("support", "tickets", use: supportTicketController.list(req:))
    tokenProtected.post("support", "tickets", use: supportTicketController.create(req:))
    tokenProtected.get("support", "tickets", ":id", use: supportTicketController.get(req:))
    tokenProtected.post(
        "support", "tickets", ":id", "archive", use: supportTicketController.archive(req:))
    // Owner DELETE = archive (guest inbox only). Floor DELETE = soft; ?hard=1 = permanent.
    tokenProtected.delete("support", "tickets", ":id", use: supportTicketController.delete(req:))
    staffProtected.put(
        "support", "tickets", ":id", "status", use: supportTicketController.updateStatus(req:))
    
    // Loyalty — self-enroll allowed; accrue/redeem admin desk only (enforced in controller)
    tokenProtected.post("loyalty", "enroll", use: loyaltyController.enroll(req:))
    tokenProtected.get("loyalty", ":id", use: loyaltyController.get(req:))
    adminProtected.post("loyalty", "accrue", use: loyaltyController.accrue(req:))
    adminProtected.post("loyalty", "redeem", use: loyaltyController.redeem(req:))

    // Team — staff: self clock + scoped reads; manager+: full roster admin
    staffProtected.get("team", use: teamController.list(req:))
    staffProtected.get("team", "time-summary", use: teamController.timeSummary(req:))
    staffProtected.get("team", "time-entries", use: teamController.listTimeEntries(req:))
    staffProtected.post("team", ":id", "clock-in", use: teamController.clockIn(req:))
    staffProtected.post("team", ":id", "clock-out", use: teamController.clockOut(req:))
    managerProtected.post("team", use: teamController.create(req:))
    managerProtected.post("team", "time-entries", use: teamController.createTimeEntry(req:))
    managerProtected.put("team", "time-entries", ":entryId", use: teamController.updateTimeEntry(req:))
    managerProtected.post("team", "time-entries", ":entryId", "approve", use: teamController.approveTimeEntry(req:))
    managerProtected.delete("team", "time-entries", ":entryId", use: teamController.deleteTimeEntry(req:))
    managerProtected.put("team", ":id", use: teamController.update(req:))
    managerProtected.delete("team", ":id", use: teamController.delete(req:))

    // People / role assignment — admin
    adminProtected.get("users", use: userController.list(req:))
    adminProtected.get("users", ":id", use: userController.get(req:))
    adminProtected.put("users", ":id", "role", use: userController.assignRole(req:))

    // Reports (finance + demand / stock outlook) — admin
    adminProtected.get("reports", "summary", use: reportsController.summary(req:))
    adminProtected.get("reports", "orders", use: reportsController.orders(req:))
    adminProtected.get("reports", "demand", use: reportsController.demand(req:))
    adminProtected.get("reports", "export", use: reportsController.exportCSV(req:))
    
    // Predictor — admin
    adminProtected.get("predictor", "export", use: predictorController.exportCSV(req:))
    adminProtected.on(
      .POST, "predictor", "models", "upload",
      body: .collect(maxSize: "200mb"),
      use: predictorController.uploadModel(req:))
    adminProtected.get("predictor", "models", use: predictorController.listModels(req:))
    adminProtected.post("predictor", "models", "activate", use: predictorController.activateModel(req:))
    adminProtected.post("predictor", "models", "delete", use: predictorController.deleteModel(req:))
    adminProtected.post("predictor", "instantiate", use: predictorController.instantiatePredictor(req:))
    adminProtected.post("predictor", "restock", "decide", use: predictorController.decideRestock(req:))
    adminProtected.get("predictor", "capabilities", use: predictorController.capabilities(req:))
    adminProtected.post("predictor", "train", use: predictorController.startTrain(req:))
    adminProtected.get("predictor", "train", use: predictorController.listTrainJobs(req:))
    adminProtected.get("predictor", "train", ":jobId", use: predictorController.getTrainJob(req:))
    adminProtected.get("predictor", "auto-train", use: predictorController.autoTrainStatus(req:))
    
    // Recipes — staff read (make-info); manager+ write
    staffProtected.get("recipes", use: recipeController.list(req:))
    staffProtected.get("recipes", ":id", use: recipeController.get(req:))
    staffProtected.get("menu", ":id", "recipes", use: recipeController.listForMenuItem(req:))
    managerProtected.post("recipes", use: recipeController.create(req:))
    managerProtected.put("recipes", ":id", use: recipeController.update(req:))
    managerProtected.delete("recipes", ":id", use: recipeController.delete(req:))
    
    // Seating — floor ops
    staffProtected.get("seating", "areas", use: seatingController.listAreas(req:))
    staffProtected.post("seating", "areas", use: seatingController.createArea(req:))
    staffProtected.get("seating", "areas", ":id", use: seatingController.getArea(req:))
    staffProtected.put("seating", "areas", ":id", use: seatingController.updateArea(req:))
    staffProtected.delete("seating", "areas", ":id", use: seatingController.deleteArea(req:))
    
    staffProtected.get("seating", "tables", use: seatingController.listTables(req:))
    staffProtected.get("seating", "areas", ":id", "tables", use: seatingController.listTablesInArea(req:))
    staffProtected.post("seating", "tables", use: seatingController.createTable(req:))
    staffProtected.get("seating", "tables", ":id", use: seatingController.getTable(req:))
    staffProtected.put("seating", "tables", ":id", use: seatingController.updateTable(req:))
    staffProtected.delete("seating", "tables", ":id", use: seatingController.deleteTable(req:))
    
    // Business config — admin (money / loyalty / payments flags)
    adminProtected.get("config", use: configController.get(req:))
    adminProtected.put("config", use: configController.upsert(req:))

    #if DEBUG
    let debugSeedController = DebugSeedController()
    adminProtected.post("debug", "seed", use: debugSeedController.seed(req:))
    adminProtected.post("debug", "reseed", use: debugSeedController.reseed(req:))
    #endif

    // Realtime WebSockets are served by ConnectionManagerKit on WS_PORT (default 8081).
}

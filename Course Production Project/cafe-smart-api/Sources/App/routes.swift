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
    let predictorController = CafePredictorController()
    let recipeController = RecipeController()
    let seatingController = SeatingController()
    let configController = ConfigController()
    
    api.post("register", use: userController.register(req:))
    api.post("login", use: userController.login(req:))
    api.post("auth", "refresh", use: userController.refreshToken(req:))
    
    // Authenticated user actions
    let tokenProtected = auth.grouped(AuthenticationMiddleware())
    tokenProtected.post("logout", use: userController.logout(req:))
    tokenProtected.put("update-password", use: userController.updatePassword(req:))
    tokenProtected.delete("account", use: userController.deleteAccount(req:))
    
    let adminProtected = tokenProtected.grouped(AdminMiddleware())
    
    // Menu
    tokenProtected.get("menu", use: menuController.list(req:))
    tokenProtected.get("menu", ":id", use: menuController.get(req:))
    adminProtected.post("menu", use: menuController.create(req:))
    adminProtected.put("menu", ":id", use: menuController.update(req:))
    adminProtected.delete("menu", ":id", use: menuController.delete(req:))
    
    // Orders
    tokenProtected.get("orders", use: orderController.list(req:))
    tokenProtected.post("orders", use: orderController.create(req:))
    tokenProtected.get("orders", ":id", use: orderController.get(req:))
    adminProtected.put("orders", ":id", "status", use: orderController.updateStatus(req:))
    adminProtected.delete("orders", ":id", use: orderController.delete(req:))
    
    // Reservations
    tokenProtected.get("reservations", use: reservationController.list(req:))
    tokenProtected.post("reservations", use: reservationController.create(req:))
    tokenProtected.get("reservations", ":id", use: reservationController.get(req:))
    adminProtected.delete("reservations", ":id", use: reservationController.delete(req:))
    
    // Inventory
    adminProtected.get("inventory", use: inventoryController.list(req:))
    adminProtected.get("inventory", ":id", use: inventoryController.get(req:))
    adminProtected.post("inventory", use: inventoryController.create(req:))
    adminProtected.put("inventory", ":id", use: inventoryController.update(req:))
    adminProtected.delete("inventory", ":id", use: inventoryController.delete(req:))
    
    // Loyalty
    tokenProtected.get("loyalty", ":id", use: loyaltyController.get(req:))
    tokenProtected.post("loyalty", "accrue", use: loyaltyController.accrue(req:))
    tokenProtected.post("loyalty", "redeem", use: loyaltyController.redeem(req:))
    adminProtected.post("loyalty", "enroll", use: loyaltyController.enroll(req:))
    
    // Predictor
    adminProtected.get("predictor", "export", use: predictorController.exportCSV(req:))
    adminProtected.post("predictor", "models", "upload", use: predictorController.uploadModel(req:))
    adminProtected.get("predictor", "models", use: predictorController.listModels(req:))
    adminProtected.post("predictor", "models", "activate", use: predictorController.activateModel(req:))
    adminProtected.post("predictor", "instantiate", use: predictorController.instantiatePredictor(req:))
    adminProtected.post("predictor", "restock", "decide", use: predictorController.decideRestock(req:))
    
    // Recipes (admin)
    adminProtected.get("recipes", use: recipeController.list(req:))
    adminProtected.post("recipes", use: recipeController.create(req:))
    adminProtected.get("recipes", ":id", use: recipeController.get(req:))
    adminProtected.put("recipes", ":id", use: recipeController.update(req:))
    adminProtected.delete("recipes", ":id", use: recipeController.delete(req:))
    adminProtected.get("menu", ":id", "recipes", use: recipeController.listForMenuItem(req:))
    
    // Seating (admin)
    adminProtected.get("seating", "areas", use: seatingController.listAreas(req:))
    adminProtected.post("seating", "areas", use: seatingController.createArea(req:))
    adminProtected.get("seating", "areas", ":id", use: seatingController.getArea(req:))
    adminProtected.put("seating", "areas", ":id", use: seatingController.updateArea(req:))
    adminProtected.delete("seating", "areas", ":id", use: seatingController.deleteArea(req:))
    
    adminProtected.get("seating", "tables", use: seatingController.listTables(req:))
    adminProtected.get("seating", "areas", ":id", "tables", use: seatingController.listTablesInArea(req:))
    adminProtected.post("seating", "tables", use: seatingController.createTable(req:))
    adminProtected.get("seating", "tables", ":id", use: seatingController.getTable(req:))
    adminProtected.put("seating", "tables", ":id", use: seatingController.updateTable(req:))
    adminProtected.delete("seating", "tables", ":id", use: seatingController.deleteTable(req:))
    
    // Business config (admin singleton)
    adminProtected.get("config", use: configController.get(req:))
    adminProtected.put("config", use: configController.upsert(req:))
    
    // WebSockets for realtime updates
    let hub = app.realtime
    adminProtected.webSocket("ws", "merchant") { req, ws in
        await hub.subscribe(topic: .merchant, ws: ws)
    }
    
    api.webSocket("ws", "customer") { req, ws in
        await hub.subscribe(topic: .customer, ws: ws)
    }
}

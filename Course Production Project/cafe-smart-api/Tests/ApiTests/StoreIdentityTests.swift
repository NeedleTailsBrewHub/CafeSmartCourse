//
//  StoreIdentityTests.swift
//  ApiTests
//
//  Inventory / recipe create → find → update by app id (store contract).
//

@preconcurrency import BSON
import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct StoreIdentityTests {

    @Test func inventoryCreateFindUpdateByAppId() async throws {
        let store = TestableMongoStore(seedDummyData: false)
        let id = ObjectId().hexString
        let created = try await store.create(
            inventoryItem: InventoryItem(
                id: id,
                sku: "ID-TEST-1",
                name: "Test Beans",
                quantity: 10,
                reorderThreshold: 2,
                unit: "bag"))
        #expect(created.id == id)

        let found = try await store.findInventory(by: id)
        #expect(found?.sku == "ID-TEST-1")
        #expect(found?.quantity == 10)

        var updated = created
        updated.quantity = 7
        let saved = try await store.update(inventoryItem: updated)
        #expect(saved.quantity == 7)
        #expect(try await store.findInventory(by: id)?.quantity == 7)
    }

    @Test func recipeCreateFindUpdateByAppId() async throws {
        let store = TestableMongoStore(seedDummyData: false)
        let menuId = ObjectId().hexString
        let id = ObjectId().hexString
        let created = try await store.create(
            recipe: Recipe(
                id: id,
                menuItemId: menuId,
                components: [.init(sku: "BEANS", unitsPerItem: 0.02)],
                createdAt: Date()))
        #expect(created.id == id)
        #expect(try await store.findRecipe(by: id)?.menuItemId == menuId)

        var updated = created
        updated.components = [.init(sku: "BEANS", unitsPerItem: 0.03)]
        _ = try await store.update(recipe: updated)
        #expect(try await store.findRecipe(by: id)?.components.first?.unitsPerItem == 0.03)
    }

    @Test func seatingCreateFindUpdateByAppId() async throws {
        let store = TestableMongoStore(seedDummyData: false)
        let areaId = ObjectId().hexString
        let area = try await store.create(
            seatingArea: SeatingArea(
                id: areaId, name: "Patio", defaultTurnMinutes: 60, active: true))
        #expect(try await store.findSeatingArea(by: areaId)?.name == "Patio")

        var next = area
        next.name = "Garden"
        _ = try await store.update(seatingArea: next)
        #expect(try await store.findSeatingArea(by: areaId)?.name == "Garden")

        let tableId = ObjectId().hexString
        let table = try await store.create(
            table: Table(
                id: tableId, areaId: areaId, name: "P1", capacity: 4,
                accessible: true, highTop: false, outside: true, active: true))
        #expect(try await store.findTable(by: tableId)?.name == "P1")
        var t2 = table
        t2.capacity = 6
        _ = try await store.update(table: t2)
        #expect(try await store.findTable(by: tableId)?.capacity == 6)
    }
}

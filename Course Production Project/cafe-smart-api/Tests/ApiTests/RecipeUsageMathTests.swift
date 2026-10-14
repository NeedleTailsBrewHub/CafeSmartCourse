//
//  RecipeUsageMathTests.swift
//  ApiTests
//
//  Spec: fractional COGS usage vs ceil stock deduction.
//

import Foundation
import Testing
@testable import cafe_smart_api

@Suite("Recipe usage math")
struct RecipeUsageMathTests {

    private func recipe(
        menuId: String = "menu-1",
        components: [RecipeComponent]
    ) -> Recipe {
        Recipe(
            id: "recipe-1",
            menuItemId: menuId,
            components: components,
            createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func exactUsageKeepsFractionalGramsAsKg() {
        let menuId = "espresso"
        let recipes = [
            menuId: recipe(
                menuId: menuId,
                components: [.init(sku: "BEANS", unitsPerItem: 0.018, wastageRate: 0.02)])
        ]
        let items = [OrderItem(menuItemId: menuId, quantity: 1)]

        let exact = OrderInventoryService.requiredUnitsExact(
            items: items, recipesByMenuId: recipes)
        #expect(abs((exact["BEANS"] ?? 0) - (0.018 * 1.02)) < 1e-12)

        let whole = OrderInventoryService.requiredUnits(
            items: items, recipesByMenuId: recipes)
        #expect(whole["BEANS"] == 1)  // ceil for physical pack/kg stock
    }

    @Test func exactAggregatesLinesBeforeCeil() {
        let menuId = "latte"
        let recipes = [
            menuId: recipe(
                menuId: menuId,
                components: [.init(sku: "MILK", unitsPerItem: 0.2)])
        ]
        // 3 drinks × 0.2 L = 0.6 L exact → ceil 1 L stock
        let items = [OrderItem(menuItemId: menuId, quantity: 3)]
        let exact = OrderInventoryService.requiredUnitsExact(
            items: items, recipesByMenuId: recipes)
        #expect(abs((exact["MILK"] ?? 0) - 0.6) < 1e-12)
        let whole = OrderInventoryService.requiredUnits(
            items: items, recipesByMenuId: recipes)
        #expect(whole["MILK"] == 1)
    }

    @Test func skipsZeroUsageComponents() {
        let menuId = "menu"
        let recipes = [
            menuId: recipe(
                menuId: menuId,
                components: [
                    .init(sku: "SUGAR", unitsPerItem: 0),
                    .init(sku: "BEANS", unitsPerItem: 0.018),
                ])
        ]
        let exact = OrderInventoryService.requiredUnitsExact(
            items: [OrderItem(menuItemId: menuId, quantity: 1)],
            recipesByMenuId: recipes)
        #expect(exact["SUGAR"] == nil)
        #expect(exact["BEANS"] != nil)
    }

    @Test func missingRecipeYieldsEmptyNeed() {
        let exact = OrderInventoryService.requiredUnitsExact(
            items: [OrderItem(menuItemId: "unknown", quantity: 2)],
            recipesByMenuId: [:])
        #expect(exact.isEmpty)
        #expect(
            OrderInventoryService.requiredUnits(
                items: [OrderItem(menuItemId: "unknown", quantity: 2)],
                recipesByMenuId: [:]).isEmpty)
    }

    @Test func fractionalCogsCentsLessThanCeilPackCost() {
        // 18 g of a $25/kg bag must not bill $25 for COGS.
        let usage = 0.018
        let costPerKgCents = 2500
        let fractional = Int((usage * Double(costPerKgCents)).rounded())
        let ceilPack = 1 * costPerKgCents
        #expect(fractional == 45)
        #expect(fractional < ceilPack)
    }
}

//
//  OrderInventoryService.swift
//  CafeSmartAPI
//
//  Recipe-based stock reservation for order create / early cancel.
//

import Foundation
import Vapor

enum OrderInventoryService {
    /// Fractional inventory units required per SKU after wastage (for COGS / analytics).
    static func requiredUnitsExact(
        items: [OrderItem],
        recipesByMenuId: [String: Recipe]
    ) -> [String: Double] {
        var needed: [String: Double] = [:]
        for line in items {
            guard let recipe = recipesByMenuId[line.menuItemId] else { continue }
            for component in recipe.components {
                let waste = max(0, component.wastageRate ?? 0)
                let units = Double(line.quantity) * component.unitsPerItem * (1 + waste)
                guard units > 0 else { continue }
                needed[component.sku, default: 0] += units
            }
        }
        return needed
    }

    /// Whole units required per SKU after wastage (ceil) — physical stock deduction only.
    static func requiredUnits(
        items: [OrderItem],
        recipesByMenuId: [String: Recipe]
    ) -> [String: Int] {
        var whole: [String: Int] = [:]
        for (sku, amount) in requiredUnitsExact(items: items, recipesByMenuId: recipesByMenuId) {
            whole[sku] = Int(amount.rounded(.up))
        }
        return whole
    }

    static func assertAndDeduct(req: Request, items: [OrderItem]) async throws {
        let recipesByMenuId = try await loadRecipes(req: req, items: items)
        let needed = requiredUnits(items: items, recipesByMenuId: recipesByMenuId)
        guard !needed.isEmpty else { return }
        try await req.store.deductInventory(bySKU: needed)
    }

    /// Soft check for checkout prepare — does not mutate stock.
    static func assertAvailable(req: Request, items: [OrderItem]) async throws {
        let recipesByMenuId = try await loadRecipes(req: req, items: items)
        let needed = requiredUnits(items: items, recipesByMenuId: recipesByMenuId)
        guard !needed.isEmpty else { return }
        let inventory = try await req.store.listInventory()
        var bySku: [String: InventoryItem] = [:]
        for item in inventory where item.deletedAt == nil {
            bySku[item.sku] = item
        }
        for (sku, units) in needed {
            guard let item = bySku[sku] else {
                throw Abort(.badRequest, reason: "Missing inventory for SKU \(sku)")
            }
            guard item.quantity >= units else {
                throw Abort(
                    .conflict,
                    reason: "Insufficient stock for \(item.name) (need \(units), have \(item.quantity))")
            }
        }
    }

    /// Restore stock for early-stage cancels (pending / preparing).
    static func restore(req: Request, items: [OrderItem]) async throws {
        let recipesByMenuId = try await loadRecipes(req: req, items: items)
        let needed = requiredUnits(items: items, recipesByMenuId: recipesByMenuId)
        guard !needed.isEmpty else { return }

        let inventory = try await req.store.listInventory()
        var bySku: [String: InventoryItem] = [:]
        for item in inventory where item.deletedAt == nil {
            bySku[item.sku] = item
        }

        for (sku, units) in needed {
            guard var item = bySku[sku] else { continue }
            item.quantity += units
            item.updatedAt = Date()
            _ = try await req.store.update(inventoryItem: item)
        }
    }

    private static func loadRecipes(req: Request, items: [OrderItem]) async throws -> [String: Recipe] {
        var map: [String: Recipe] = [:]
        for line in items {
            if map[line.menuItemId] != nil { continue }
            let recipes = try await req.store.findRecipes(menuItemId: line.menuItemId)
            if let first = recipes.first {
                map[line.menuItemId] = first
            }
        }
        return map
    }
}

enum OrderStatusFSM {
    static func pipelineRank(_ status: OrderStatus) -> Int {
        switch status {
        case .pending: return 0
        case .preparing: return 1
        case .ready: return 2
        case .completed, .canceled: return 3
        }
    }

    static func isTerminal(_ status: OrderStatus) -> Bool {
        status == .completed || status == .canceled
    }

    /// Admin kitchen transitions: forward one step, or cancel from a non-terminal stage.
    static func canAdminTransition(from: OrderStatus, to: OrderStatus) -> Bool {
        if from == to { return true }
        if isTerminal(from) { return false }
        if to == .canceled { return true }
        switch (from, to) {
        case (.pending, .preparing), (.preparing, .ready), (.ready, .completed):
            return true
        default:
            return false
        }
    }

    static func isEarlyCancelStage(_ status: OrderStatus) -> Bool {
        status == .pending || status == .preparing
    }
}

//
//  CartViewModel.swift
//  CafeSmartDev
//

import Foundation
import Observation
import SkipFuse

/// Shared guest cart. Keeping this at the application level prevents navigation
/// from silently discarding an in-progress order.
@MainActor
@Observable
final class CartViewModel {
    private static let storageKey = "cafeSmart.cart.v1"

    var lines: [CartLine] = [] {
        didSet { persist() }
    }

    init() {
        restore()
    }

    var itemCount: Int {
        lines.reduce(0) { $0 + $1.quantity }
    }

    var totalCents: Int {
        lines.reduce(0) { $0 + $1.lineCents }
    }

    var isEmpty: Bool {
        lines.isEmpty
    }

    func add(item: MenuItem, quantity: Int = 1, size: MenuSizeOption? = nil) {
        let delta = size?.priceDeltaCents ?? 0
        if let index = lines.firstIndex(where: {
            $0.item.id == item.id && $0.sizeDeltaCents == delta
        }) {
            lines[index].quantity = min(20, lines[index].quantity + quantity)
        } else {
            lines.append(
                CartLine(
                    item: item,
                    quantity: min(20, quantity),
                    sizeDeltaCents: delta,
                    sizeName: size?.name
                )
            )
        }
    }

    func increment(_ line: CartLine) {
        update(line, quantity: line.quantity + 1)
    }

    func decrement(_ line: CartLine) {
        if line.quantity <= 1 {
            remove(line)
        } else {
            update(line, quantity: line.quantity - 1)
        }
    }

    func remove(_ line: CartLine) {
        lines.removeAll { $0.id == line.id }
    }

    func removeUnavailableItems(using menuItems: [MenuItem]) -> Int {
        let availableIDs = Set(menuItems.filter(\.isAvailable).map(\.id))
        let countBefore = lines.count
        lines.removeAll { !availableIDs.contains($0.item.id) }
        return countBefore - lines.count
    }

    func clear() {
        lines.removeAll()
    }

    private func update(_ line: CartLine, quantity: Int) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[index].quantity = min(20, max(1, quantity))
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let storedLines = try? JSONDecoder().decode([CartLine].self, from: data)
        else {
            return
        }
        lines = storedLines
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

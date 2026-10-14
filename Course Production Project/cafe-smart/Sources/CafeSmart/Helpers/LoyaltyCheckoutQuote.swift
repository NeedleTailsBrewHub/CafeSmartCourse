//
//  LoyaltyCheckoutQuote.swift
//  CafeSmart
//
//  Client-side estimate of checkout loyalty (server is authoritative).
//

#if SKIP
import SkipFoundation
#else
import Foundation
import VenueSmartKit
#endif

struct LoyaltyCheckoutQuote: Equatable, Sendable {
    var subtotalCents: Int
    var discountCents: Int
    var payableCents: Int
    var pointsSpent: Int
    var pointsEarned: Int
    var redeemableUnitCount: Int

    static func quote(
        lines: [CartLine],
        balance: Int,
        earnPerUnit: Int,
        programEnabled: Bool,
        usePoints: Bool
    ) -> LoyaltyCheckoutQuote {
        struct Unit {
            let unitPriceCents: Int
            let redeemCost: Int
            var earns: Bool
        }

        var units: [Unit] = []
        var subtotal = 0
        for line in lines {
            let unitPrice = line.item.priceCents + line.sizeDeltaCents
            for _ in 0..<line.quantity {
                units.append(
                    Unit(
                        unitPriceCents: unitPrice,
                        redeemCost: line.item.redeemPointsCost,
                        earns: line.item.earnsLoyaltyPoints))
                subtotal += unitPrice
            }
        }

        guard programEnabled else {
            return LoyaltyCheckoutQuote(
                subtotalCents: subtotal,
                discountCents: 0,
                payableCents: subtotal,
                pointsSpent: 0,
                pointsEarned: 0,
                redeemableUnitCount: 0)
        }

        var discount = 0
        var spent = 0
        var remaining = max(0, balance)
        let redeemableCount = units.filter { $0.redeemCost > 0 }.count

        if usePoints && remaining > 0 {
            let indexes = units.indices
                .filter { units[$0].redeemCost > 0 }
                .sorted { units[$0].redeemCost < units[$1].redeemCost }
            for idx in indexes {
                let cost = units[idx].redeemCost
                guard remaining >= cost else { continue }
                remaining -= cost
                spent += cost
                discount += units[idx].unitPriceCents
                units[idx].earns = false
            }
        }

        let earned = units.filter(\.earns).count * max(1, earnPerUnit)
        return LoyaltyCheckoutQuote(
            subtotalCents: subtotal,
            discountCents: discount,
            payableCents: max(0, subtotal - discount),
            pointsSpent: spent,
            pointsEarned: earned,
            redeemableUnitCount: redeemableCount)
    }
}

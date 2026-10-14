//
//  OrderCheckoutService.swift
//  CafeSmartAPI
//
//  Shared pricing + order write for pay-at-pickup create and prepaid fulfill.
//

@preconcurrency import BSON
import Vapor

struct OrderCheckoutDraft: Sendable {
    var pricedItems: [OrderItem]
    var quote: CheckoutQuote
    var customerName: String?
    var pickupTime: Date?
    var channel: Order.OrderChannel?
    var serviceType: Order.ServiceType?
    var tableId: String?
    var guests: Int?
    var reservationId: String?
}

enum OrderCheckoutService {
    /// Server-authoritative quote (no inventory deduct, no loyalty ledger writes).
    static func quote(
        req: Request,
        userId: String,
        items: [OrderItem],
        useLoyaltyPoints: Bool?,
        customerName: String? = nil,
        pickupTime: Date? = nil,
        channel: Order.OrderChannel? = nil,
        serviceType: Order.ServiceType? = nil,
        tableId: String? = nil,
        guests: Int? = nil,
        reservationId: String? = nil
    ) async throws -> OrderCheckoutDraft {
        guard !items.isEmpty else {
            throw Abort(.badRequest, reason: "Order requires at least one item")
        }

        let config = try await req.store.getBusinessConfig()
        let programOn = config?.isLoyaltyProgramEnabled == true
        let earnPerUnit = config?.earnPointsPerUnit ?? 5
        let wantsRedeem = useLoyaltyPoints == true

        struct PricedUnit {
            let unitPriceCents: Int
            let redeemCost: Int
            var earns: Bool
        }

        var units: [PricedUnit] = []
        var pricedItems: [OrderItem] = []
        var subtotalCents = 0

        for line in items {
            guard line.quantity > 0 else {
                throw Abort(.badRequest, reason: "Item quantity must be > 0")
            }
            guard let menu = try await req.store.findMenuItem(by: line.menuItemId) else {
                throw Abort(.badRequest, reason: "Unknown menu item")
            }
            guard menu.deletedAt == nil else {
                throw Abort(.badRequest, reason: "Menu item is no longer offered")
            }
            guard menu.isAvailable else {
                throw Abort(.badRequest, reason: "Menu item unavailable: \(menu.name)")
            }
            let sizeDelta = try resolvedSizeDeltaCents(menu: menu, sizeName: line.sizeName)
            let unitPrice = max(0, menu.priceCents + sizeDelta)
            pricedItems.append(
                OrderItem(
                    menuItemId: menu.id,
                    name: line.name ?? menu.name,
                    quantity: line.quantity,
                    notes: line.notes,
                    unitPriceCents: unitPrice,
                    sizeName: line.sizeName))
            for _ in 0..<line.quantity {
                units.append(
                    PricedUnit(
                        unitPriceCents: unitPrice,
                        redeemCost: menu.redeemPointsCost,
                        earns: menu.earnsLoyaltyPoints))
                subtotalCents += unitPrice
            }
        }

        var discountCents = 0
        var pointsSpent = 0
        var balance = 0

        if programOn {
            try? await LoyaltyLedger.ensureAccount(req: req, userId: userId)
            balance = (try? await LoyaltyLedger.currentPoints(req: req, userId: userId)) ?? 0
        }

        if programOn && wantsRedeem && balance > 0 {
            let redeemableIndexes = units.indices
                .filter { units[$0].redeemCost > 0 }
                .sorted { units[$0].redeemCost < units[$1].redeemCost }
            for idx in redeemableIndexes {
                let cost = units[idx].redeemCost
                guard balance >= cost else { continue }
                balance -= cost
                pointsSpent += cost
                discountCents += units[idx].unitPriceCents
                units[idx].earns = false
            }
        }

        let pointsEarned = programOn ? units.filter(\.earns).count * earnPerUnit : 0
        if !programOn {
            discountCents = 0
            pointsSpent = 0
        }
        let totalCents = max(0, subtotalCents - discountCents)

        return OrderCheckoutDraft(
            pricedItems: pricedItems,
            quote: CheckoutQuote(
                subtotalCents: subtotalCents,
                loyaltyDiscountCents: discountCents,
                totalCents: totalCents,
                loyaltyPointsSpent: pointsSpent,
                loyaltyPointsEarned: pointsEarned),
            customerName: customerName,
            pickupTime: pickupTime,
            channel: channel,
            serviceType: serviceType,
            tableId: tableId,
            guests: guests,
            reservationId: reservationId)
    }

    /// Deduct stock, apply loyalty ledger, persist order, publish realtime.
    static func placeOrder(
        req: Request,
        userId: String,
        draft: OrderCheckoutDraft,
        paymentStatus: OrderPaymentStatus,
        stripePaymentIntentId: String? = nil,
        checkoutSessionId: String? = nil,
        paidAt: Date? = nil
    ) async throws -> Order {
        try await OrderInventoryService.assertAndDeduct(req: req, items: draft.pricedItems)

        let pointsSpent = draft.quote.loyaltyPointsSpent
        let pointsEarned = draft.quote.loyaltyPointsEarned
        if pointsSpent > 0 {
            try await LoyaltyLedger.spend(req: req, userId: userId, points: pointsSpent)
        }
        if pointsEarned > 0 {
            try? await LoyaltyLedger.ensureAndAccrue(req: req, userId: userId, points: pointsEarned)
        }

        let now = Date()
        let model = Order(
            id: ObjectId().hexString,
            status: .pending,
            customerName: draft.customerName,
            customerUserId: userId,
            items: draft.pricedItems,
            pickupTime: draft.pickupTime,
            channel: draft.channel,
            serviceType: draft.serviceType,
            tableId: draft.tableId,
            guests: draft.guests,
            reservationId: draft.reservationId,
            createdAt: now,
            subtotalCents: draft.quote.subtotalCents,
            loyaltyDiscountCents: draft.quote.loyaltyDiscountCents,
            totalCents: draft.quote.amountDueCents,
            loyaltyPointsSpent: pointsSpent,
            loyaltyPointsEarned: pointsEarned,
            paymentStatus: paymentStatus,
            stripePaymentIntentId: stripePaymentIntentId,
            checkoutSessionId: checkoutSessionId,
            paidAt: paidAt,
            taxCents: draft.quote.taxCents)
        let created = try await req.store.create(order: model)
        try? await AuditService.write(
            req: req, entityType: "order", entityId: created.id, action: "create",
            summary: "total=\(draft.quote.totalCents) payment=\(paymentStatus.rawValue)")
        await req.application.realtime.publish(.order(.created(created)), to: .merchant)
        await req.application.realtime.publish(
            .order(.created(created)), to: .customer, userId: created.customerUserId)
        return created
    }

    static func resolvedSizeDeltaCents(menu: MenuItem, sizeName: String?) throws -> Int {
        guard let raw = sizeName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return 0 }
        guard let options = menu.sizeOptions, !options.isEmpty else {
            throw Abort(.badRequest, reason: "Size not offered for \(menu.name)")
        }
        guard let match = options.first(where: {
            $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw Abort(.badRequest, reason: "Unknown size '\(raw)' for \(menu.name)")
        }
        return match.priceDeltaCents
    }
}

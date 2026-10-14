//
//  CheckoutFulfillment.swift
//  CafeSmartAPI
//
//  Single path used by confirm + Stripe webhook.
//

import Foundation
import Vapor

enum CheckoutFulfillment {
    /// - Parameter webhookMode: When true, terminal failures return nil (HTTP 200) after recording
    ///   so Stripe does not retry forever; confirm path still surfaces Abort to the client.
    @discardableResult
    static func fulfill(
        req: Request,
        session: CheckoutSession,
        webhookMode: Bool = false
    ) async throws -> Order? {
        if session.status == .fulfilled, let orderId = session.orderId,
            let existing = try await req.store.findOrder(by: orderId)
        {
            return existing
        }

        switch session.status {
        case .fulfilled:
            return nil
        case .expired:
            if webhookMode { return nil }
            throw Abort(.gone, reason: "Checkout session expired")
        case .failed:
            if webhookMode { return nil }
            throw Abort(.conflict, reason: "Checkout session failed; start a new checkout")
        case .fulfilling:
            // Another worker is placing the order — wait briefly for orderId.
            if let order = try await waitForFulfilledOrder(req: req, sessionId: session.id) {
                return order
            }
            if webhookMode { return nil }
            throw Abort(.conflict, reason: "Checkout is already being fulfilled")
        case .pending:
            break
        }

        if session.expiresAt < Date() {
            var expired = session
            expired.status = .expired
            _ = try await req.store.update(checkoutSession: expired)
            if webhookMode { return nil }
            throw Abort(.gone, reason: "Checkout session expired")
        }

        guard let claimed = try await req.store.claimCheckoutSessionForFulfillment(id: session.id)
        else {
            // Lost race — re-read and return idempotent result if possible.
            if let latest = try await req.store.findCheckoutSession(by: session.id) {
                return try await fulfill(req: req, session: latest, webhookMode: webhookMode)
            }
            return nil
        }

        do {
            try await validatePayment(req: req, session: claimed)
            let draft = try await OrderCheckoutService.quote(
                req: req,
                userId: claimed.userId,
                items: claimed.items,
                useLoyaltyPoints: claimed.useLoyaltyPoints,
                customerName: claimed.customerName,
                pickupTime: claimed.pickupTime,
                channel: claimed.channel,
                serviceType: claimed.serviceType,
                tableId: claimed.tableId,
                guests: claimed.guests,
                reservationId: claimed.reservationId)

            guard draft.quote.totalCents == claimed.quote.totalCents else {
                throw Abort(.conflict, reason: "Quote changed since prepare; restart checkout")
            }

            // Apply frozen tax from prepare (re-quote is merchandise-only).
            var priced = draft
            priced.quote.taxCents = claimed.quote.taxCents

            let amount = claimed.amountCents
            guard priced.quote.amountDueCents == amount else {
                throw Abort(.conflict, reason: "Charged amount does not match quote")
            }
            let paymentStatus: OrderPaymentStatus = amount == 0 ? .waived : .paid
            let order = try await OrderCheckoutService.placeOrder(
                req: req,
                userId: claimed.userId,
                draft: priced,
                paymentStatus: paymentStatus,
                stripePaymentIntentId: claimed.paymentIntentId,
                checkoutSessionId: claimed.id,
                paidAt: Date())

            if let taxCalc = claimed.taxCalculationId, !taxCalc.isEmpty {
                try? await req.application.stripeClient.createTaxTransaction(
                    fromCalculationId: taxCalc, reference: order.id)
            }

            var fulfilled = claimed
            fulfilled.status = .fulfilled
            fulfilled.orderId = order.id
            _ = try await req.store.update(checkoutSession: fulfilled)
            return order
        } catch {
            var failed = claimed
            failed.status = .failed
            _ = try? await req.store.update(checkoutSession: failed)
            if claimed.amountCents > 0, let piId = claimed.paymentIntentId {
                do {
                    try await req.application.stripeClient.refundPaymentIntent(id: piId)
                    req.logger.warning(
                        "Refunded PaymentIntent after fulfill failure",
                        metadata: [
                            "paymentIntentId": .string(piId),
                            "sessionId": .string(claimed.id),
                        ])
                } catch {
                    req.logger.error(
                        "CRITICAL: fulfill failed and refund failed — manual intervention required",
                        metadata: [
                            "paymentIntentId": .string(piId),
                            "sessionId": .string(claimed.id),
                            "error": .string("\(error)"),
                        ])
                }
            }
            if webhookMode {
                req.logger.error(
                    "Webhook fulfill failed (session marked failed)",
                    metadata: [
                        "sessionId": .string(claimed.id),
                        "error": .string("\(error)"),
                    ])
                return nil
            }
            throw error
        }
    }

    static func fulfillByPaymentIntentId(req: Request, paymentIntentId: String) async throws -> Order? {
        guard let session = try await req.store.findCheckoutSession(byPaymentIntentId: paymentIntentId)
        else { return nil }
        return try await fulfill(req: req, session: session, webhookMode: true)
    }

    private static func validatePayment(req: Request, session: CheckoutSession) async throws {
        let amount = session.amountCents
        guard amount > 0 else { return }
        guard let piId = session.paymentIntentId else {
            throw Abort(.paymentRequired, reason: "Missing PaymentIntent")
        }
        let pi = try await req.application.stripeClient.retrievePaymentIntent(id: piId)
        guard pi.status == "succeeded" else {
            throw Abort(.paymentRequired, reason: "Payment not completed")
        }
        guard pi.amount == amount else {
            throw Abort(.conflict, reason: "Payment amount mismatch")
        }
        let expectedCurrency = session.currency.lowercased()
        guard pi.currency.lowercased() == expectedCurrency else {
            throw Abort(.conflict, reason: "Payment currency mismatch")
        }
        if let metaSession = pi.metadata["checkoutSessionId"], metaSession != session.id {
            throw Abort(.conflict, reason: "PaymentIntent metadata mismatch")
        }
        if let metaUser = pi.metadata["userId"], metaUser != session.userId {
            throw Abort(.conflict, reason: "PaymentIntent user mismatch")
        }
    }

    private static func waitForFulfilledOrder(req: Request, sessionId: String) async throws -> Order? {
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(50))
            if let latest = try await req.store.findCheckoutSession(by: sessionId),
                latest.status == .fulfilled,
                let orderId = latest.orderId,
                let order = try await req.store.findOrder(by: orderId)
            {
                return order
            }
        }
        return nil
    }
}

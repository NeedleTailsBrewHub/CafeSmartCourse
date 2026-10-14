//
//  CheckoutController.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Vapor

actor CheckoutController {
    func capabilities(req: Request) async throws -> CheckoutCapabilities {
        let config = try await req.store.getBusinessConfig()
        return PaymentsPolicy.capabilities(config: config)
    }

    func prepare(req: Request) async throws -> CheckoutSessionResponse {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        let config = try await req.store.getBusinessConfig()
        guard PaymentsPolicy.prepaidEnabled(config: config) else {
            throw Abort(.serviceUnavailable, reason: "Prepaid payments disabled")
        }

        let body = try req.content.decode(CreateCheckoutSessionRequest.self)
        let draft = try await OrderCheckoutService.quote(
            req: req,
            userId: user.id,
            items: body.items,
            useLoyaltyPoints: body.useLoyaltyPoints,
            customerName: body.customerName,
            pickupTime: body.pickupTime,
            channel: body.channel,
            serviceType: body.serviceType,
            tableId: body.tableId,
            guests: body.guests,
            reservationId: body.reservationId)

        // Soft stock check — hard deduct happens at fulfill.
        try await OrderInventoryService.assertAvailable(req: req, items: draft.pricedItems)

        var quote = draft.quote
        let currency = PaymentsPolicy.currency
        let now = Date()
        let expiresAt = now.addingTimeInterval(30 * 60)
        let sessionId = ObjectId().hexString

        var paymentIntentId: String?
        var clientSecret: String?
        var customerId: String?
        var ephemeralKey: String?
        var taxCalculationId: String?

        let merchandise = quote.totalCents
        if merchandise > 0 {
            let stripe = req.application.stripeClient
            let cus = try await stripe.ensureCustomer(
                userId: user.id, email: user.email, existingCustomerId: user.stripeCustomerId)
            if user.stripeCustomerId != cus {
                var updated = user
                updated.stripeCustomerId = cus
                _ = try await req.store.updateUser(updated)
            }
            customerId = cus
            ephemeralKey = try await stripe.createEphemeralKey(customerId: cus)

            var chargeCents = merchandise
            if PaymentsPolicy.stripeTaxEnabled {
                let ip = Self.clientIP(req)
                do {
                    let calc = try await stripe.createTaxCalculation(
                        currency: currency,
                        amountCents: merchandise,
                        reference: sessionId,
                        taxCode: PaymentsPolicy.stripeTaxCode,
                        address: PaymentsPolicy.stripeTaxAddress,
                        customerIP: ip)
                    quote.taxCents = calc.taxAmountExclusive
                    chargeCents = calc.amountTotal
                    taxCalculationId = calc.id
                } catch {
                    req.logger.warning(
                        "Stripe Tax calculation failed; charging merchandise only",
                        metadata: ["error": .string("\(error)")])
                    quote.taxCents = 0
                }
            }

            let pi = try await stripe.createPaymentIntent(
                amountCents: chargeCents,
                currency: currency,
                customerId: cus,
                metadata: [
                    "checkoutSessionId": sessionId,
                    "userId": user.id,
                ],
                taxCalculationId: taxCalculationId)
            paymentIntentId = pi.id
            clientSecret = pi.clientSecret
        }

        let amount = quote.amountDueCents
        let session = CheckoutSession(
            id: sessionId,
            userId: user.id,
            customerName: body.customerName,
            items: draft.pricedItems,
            pickupTime: body.pickupTime,
            channel: body.channel,
            serviceType: body.serviceType,
            tableId: body.tableId,
            guests: body.guests,
            reservationId: body.reservationId,
            useLoyaltyPoints: body.useLoyaltyPoints == true,
            quote: quote,
            paymentIntentId: paymentIntentId,
            amountCents: amount,
            currency: currency,
            status: .pending,
            createdAt: now,
            expiresAt: expiresAt,
            taxCalculationId: taxCalculationId)
        do {
            _ = try await req.store.create(checkoutSession: session)
        } catch {
            if let piId = paymentIntentId {
                try? await req.application.stripeClient.cancelPaymentIntent(id: piId)
            }
            throw error
        }

        guard let publishable = PaymentsPolicy.stripePublishableKey else {
            throw Abort(.serviceUnavailable, reason: "Stripe publishable key missing")
        }

        return CheckoutSessionResponse(
            sessionId: sessionId,
            publishableKey: publishable,
            customerId: customerId,
            ephemeralKeySecret: ephemeralKey,
            paymentIntentClientSecret: clientSecret,
            paymentIntentId: paymentIntentId,
            amountCents: amount,
            currency: currency,
            quote: quote,
            expiresAt: expiresAt)
    }

    private static func clientIP(_ req: Request) -> String? {
        if let forwarded = req.headers.first(name: .xForwardedFor) {
            let first = forwarded.split(separator: ",").first.map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let first, !first.isEmpty { return first }
        }
        return req.remoteAddress?.ipAddress
    }

    func confirm(req: Request) async throws -> Order {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        let body = try req.content.decode(ConfirmCheckoutRequest.self)
        guard let session = try await req.store.findCheckoutSession(by: body.sessionId) else {
            throw Abort(.notFound)
        }
        guard session.userId == user.id else {
            throw Abort(.forbidden, reason: "Not your checkout session")
        }
        guard let order = try await CheckoutFulfillment.fulfill(req: req, session: session)
        else {
            throw Abort(.conflict, reason: "Checkout could not be fulfilled")
        }
        return order
    }

    /// Stripe webhook — raw body + signature. Uses same fulfill as confirm.
    func webhook(req: Request) async throws -> HTTPStatus {
        guard let secret = PaymentsPolicy.stripeWebhookSecret else {
            throw Abort(.serviceUnavailable, reason: "Webhook secret not configured")
        }
        let sig = req.headers.first(name: "Stripe-Signature") ?? ""
        // Route uses `body: .collect`, so payload is already buffered.
        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "Empty webhook body")
        }
        let data = Data(buffer: buffer)
        guard StripeWebhookVerifier.verify(payload: data, header: sig, secret: secret) else {
            throw Abort(.badRequest, reason: "Invalid Stripe signature")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String,
            let obj = (json["data"] as? [String: Any])?["object"] as? [String: Any],
            let piId = obj["id"] as? String
        else {
            return .ok
        }
        if type == "payment_intent.succeeded" {
            if let fake = req.application.fakeStripe {
                await fake.markSucceeded(piId)
            }
            _ = try await CheckoutFulfillment.fulfillByPaymentIntentId(
                req: req, paymentIntentId: piId)
        }
        return .ok
    }
}

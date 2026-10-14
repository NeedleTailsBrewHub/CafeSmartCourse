//
//  PaymentTests.swift
//  ApiTests
//
//  TDD ladder for unified prepaid checkout (FakeStripe only).
//

import Foundation
import NIOHTTP1
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct PaymentTests {

    private func makePaymentsApp(adminEmail: String) async throws -> Application {
        try await APITestHelpers.makeApp(adminEmail: adminEmail) { _ in
            APITestHelpers.enableFakePaymentsEnv()
        }
    }

    private func enableMerchantPrepaid(app: Application, adminToken: String) async throws {
        let staffing = StaffingRules(
            ordersPerBaristaPerHour: 40,
            ordersPerBakerPerHour: 30,
            guestsPerHostPerHour: 50)
        let cfg = BusinessConfig(
            id: "cfg-payments",
            timezone: "America/New_York",
            hours: [BusinessHours(weekday: 2, open: "07:00", close: "19:00")],
            seatingCapacity: 40,
            staffing: staffing,
            prepaidPaymentsEnabled: true)
        let res = try await APITestHelpers.request(
            app, .PUT, "/api/auth/config", token: adminToken, body: cfg)
        #expect(res.status == .ok)
    }

    private func seedMenu(
        app: Application,
        adminToken: String,
        priceCents: Int = 500
    ) async throws -> MenuItem {
        let res = try await APITestHelpers.request(
            app, .POST, "/api/auth/menu",
            token: adminToken,
            body: CreateMenuItemRequest(
                name: "Checkout Latte",
                priceCents: priceCents,
                isAvailable: true))
        #expect(res.status == .ok || res.status == .created)
        return try APITestHelpers.decodeBody(MenuItem.self, from: res)
    }

    // MARK: - Rung 1: quote parity (prepare vs pay-at-pickup)

    @Test func prepareQuoteMatchesPayAtPickupTotal() async throws {
        let adminEmail = "pay-quote-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-quote-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 500)

            let items = [
                OrderItem(menuItemId: menu.id, name: menu.name, quantity: 2, unitPriceCents: 1)
            ]
            let prepareBody = CreateCheckoutSessionRequest(
                customerName: "Guest",
                items: items,
                channel: .pickup,
                serviceType: .barista)
            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare", token: userToken, body: prepareBody)
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            #expect(session.amountCents == 1000)
            #expect(session.quote.totalCents == 1000)
            #expect(session.paymentIntentId != nil)
            #expect(session.paymentIntentClientSecret != nil)

            let orderBody = CreateOrderRequest(
                customerName: "Guest",
                items: items,
                channel: .pickup,
                serviceType: .barista,
                paymentMode: .payAtPickup)
            let orderRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders", token: userToken, body: orderBody)
            #expect(orderRes.status == .ok || orderRes.status == .created)
            let order = try APITestHelpers.decodeBody(Order.self, from: orderRes)
            #expect(order.totalCents == session.quote.totalCents)
            #expect(order.paymentStatus == .unpaid)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - Rung 2b: feature flag

    @Test func capabilitiesOffByDefaultAndPrepare503() async throws {
        let adminEmail = "pay-flag-off-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-flag-off-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let capsRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/checkout/capabilities", token: userToken)
            #expect(capsRes.status == .ok)
            let caps = try APITestHelpers.decodeBody(CheckoutCapabilities.self, from: capsRes)
            #expect(caps.prepaidAvailable == false)
            #expect(caps.prepaidEnabled == false)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(prepRes.status == .serviceUnavailable)

            let orderRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "Pickup",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup,
                    paymentMode: .payAtPickup))
            #expect(orderRes.status == .ok || orderRes.status == .created)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func opsKillSwitchBlocksEvenWhenMerchantToggleOn() async throws {
        let adminEmail = "pay-ops-off-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-ops-off-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)

            let capsRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/checkout/capabilities", token: userToken)
            let caps = try APITestHelpers.decodeBody(CheckoutCapabilities.self, from: capsRes)
            #expect(caps.prepaidAvailable == false)
            #expect(caps.prepaidEnabled == false)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func merchantToggleEnablesPrepareWithOpsOn() async throws {
        let adminEmail = "pay-merchant-on-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-merchant-on-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            var capsRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/checkout/capabilities", token: userToken)
            var caps = try APITestHelpers.decodeBody(CheckoutCapabilities.self, from: capsRes)
            #expect(caps.prepaidAvailable == true)
            #expect(caps.prepaidEnabled == false)

            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            capsRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/checkout/capabilities", token: userToken)
            caps = try APITestHelpers.decodeBody(CheckoutCapabilities.self, from: capsRes)
            #expect(caps.prepaidEnabled == true)

            // Persist + re-read config (regression: Mongo upsert used to no-op).
            let getRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/config", token: adminToken)
            #expect(getRes.status == .ok)
            let fetched = try APITestHelpers.decodeBody(BusinessConfig.self, from: getRes)
            #expect(fetched.prepaidPaymentsEnabled == true)

            var again = fetched
            again.prepaidPaymentsEnabled = true
            let putRes = try await APITestHelpers.request(
                app, .PUT, "/api/auth/config", token: adminToken, body: again)
            #expect(putRes.status == .ok)
            let putBody = try APITestHelpers.decodeBody(BusinessConfig.self, from: putRes)
            #expect(putBody.prepaidPaymentsEnabled == true)
            let get2 = try await APITestHelpers.request(
                app, .GET, "/api/auth/config", token: adminToken)
            let fetched2 = try APITestHelpers.decodeBody(BusinessConfig.self, from: get2)
            #expect(fetched2.prepaidPaymentsEnabled == true)
            #expect(fetched2.id == putBody.id)

            let menu = try await seedMenu(app: app, adminToken: adminToken)
            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(prepRes.status == .ok)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - Rung 3: confirm fulfill

    @Test func confirmSucceededCreatesPaidOrderIdempotent() async throws {
        let adminEmail = "pay-confirm-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-confirm-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 450)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    customerName: "Paid Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup,
                    serviceType: .barista))
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            guard let piId = session.paymentIntentId else {
                Issue.record("expected PaymentIntent")
                return
            }
            await app.fakeStripe?.markSucceeded(piId)

            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .ok)
            let order = try APITestHelpers.decodeBody(Order.self, from: confirmRes)
            #expect(order.paymentStatus == .paid)
            #expect(order.stripePaymentIntentId == piId)
            #expect(order.checkoutSessionId == session.sessionId)
            #expect(order.totalCents == 450)
            #expect(order.status == .pending)

            let again = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(again.status == .ok)
            let order2 = try APITestHelpers.decodeBody(Order.self, from: again)
            #expect(order2.id == order.id)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func confirmRejectsUnpaidPaymentIntent() async throws {
        let adminEmail = "pay-402-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-402-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            // Fake leaves PI as requires_payment_method
            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .paymentRequired)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func confirmRejectsWrongUser() async throws {
        let adminEmail = "pay-403-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-403-owner@example.com")
            let (_, otherToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-403-other@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            if let pi = session.paymentIntentId { await app.fakeStripe?.markSucceeded(pi) }

            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: otherToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .forbidden)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - Rung 4: webhook

    @Test func webhookFulfillsOnceAndRejectsBadSignature() async throws {
        let adminEmail = "pay-wh-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-wh-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 300)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            let piId = try #require(session.paymentIntentId)

            let payloadDict: [String: Any] = [
                "type": "payment_intent.succeeded",
                "data": ["object": ["id": piId, "status": "succeeded"]],
            ]
            let payload = try JSONSerialization.data(withJSONObject: payloadDict)
            let secret = "whsec_test_fake"
            let goodSig = StripeWebhookVerifier.sign(payload: payload, secret: secret)

            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: "Stripe-Signature", value: goodSig)
            headers.replaceOrAdd(name: .contentType, value: "application/json")
            let whRes = try await APITestHelpers.requestRaw(
                app, .POST, "/api/webhooks/stripe", headers: headers, body: payload)
            #expect(whRes.status == .ok)

            let stored = try await app.mongoStore.findCheckoutSession(by: session.sessionId)
            #expect(stored?.status == .fulfilled)
            #expect(stored?.orderId != nil)
            let orderId = try #require(stored?.orderId)
            let order = try await app.mongoStore.findOrder(by: orderId)
            #expect(order?.paymentStatus == .paid)

            // Replay — no duplicate
            let replay = try await APITestHelpers.requestRaw(
                app, .POST, "/api/webhooks/stripe", headers: headers, body: payload)
            #expect(replay.status == .ok)
            let stored2 = try await app.mongoStore.findCheckoutSession(by: session.sessionId)
            #expect(stored2?.orderId == orderId)

            var badHeaders = HTTPHeaders()
            badHeaders.replaceOrAdd(name: "Stripe-Signature", value: "t=1,v1=deadbeef")
            let bad = try await APITestHelpers.requestRaw(
                app, .POST, "/api/webhooks/stripe", headers: badHeaders, body: payload)
            #expect(bad.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - Rung 5: payAtPickup regression

    @Test func rejectPayAtPickupWhenMerchantDisables() async throws {
        let adminEmail = "pay-pickup-off-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-pickup-off-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)

            let staffing = StaffingRules(
                ordersPerBaristaPerHour: 40,
                ordersPerBakerPerHour: 30,
                guestsPerHostPerHour: 50)
            var cfg = BusinessConfig(
                id: "cfg-pickup-off",
                timezone: "America/New_York",
                hours: [BusinessHours(weekday: 2, open: "07:00", close: "19:00")],
                seatingCapacity: 40,
                staffing: staffing)
            cfg.prepaidPaymentsEnabled = true
            cfg.payAtPickupEnabled = false
            let put = try await APITestHelpers.request(
                app, .PUT, "/api/auth/config", token: adminToken, body: cfg)
            #expect(put.status == .ok)

            let capsRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/checkout/capabilities", token: userToken)
            let caps = try APITestHelpers.decodeBody(CheckoutCapabilities.self, from: capsRes)
            #expect(caps.prepaidEnabled == true)
            #expect(caps.isPayAtPickupEnabled == false)

            let menu = try await seedMenu(app: app, adminToken: adminToken)
            let orderRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "Must Pay Now",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup,
                    paymentMode: .payAtPickup))
            #expect(orderRes.status == .forbidden)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func rejectPrepaidOnOrdersEndpoint() async throws {
        let adminEmail = "pay-reject-prepaid-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-reject-prepaid-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/orders",
                token: userToken,
                body: CreateOrderRequest(
                    customerName: "Nope",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup,
                    paymentMode: .prepaid))
            #expect(res.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func prepareRejectsEmptyCart() async throws {
        let adminEmail = "pay-empty-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-empty-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)

            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(items: [], channel: .pickup))
            #expect(res.status == .badRequest)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func confirmExpiredSessionReturnsGone() async throws {
        let adminEmail = "pay-410-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (user, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-410-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            if let pi = session.paymentIntentId { await app.fakeStripe?.markSucceeded(pi) }

            var stored = try #require(try await app.mongoStore.findCheckoutSession(by: session.sessionId))
            stored.expiresAt = Date().addingTimeInterval(-60)
            _ = try await app.mongoStore.update(checkoutSession: stored)

            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .gone)
            _ = user
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func zeroDollarLoyaltySkipsPaymentIntentAndWaives() async throws {
        let adminEmail = "pay-zero-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (user, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-zero-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)

            // Loyalty on + enough points to cover a redeemable item.
            let staffing = StaffingRules(
                ordersPerBaristaPerHour: 40,
                ordersPerBakerPerHour: 30,
                guestsPerHostPerHour: 50)
            var cfg = BusinessConfig(
                id: "cfg-zero",
                timezone: "America/New_York",
                hours: [BusinessHours(weekday: 2, open: "07:00", close: "19:00")],
                seatingCapacity: 40,
                staffing: staffing,
                loyaltyEnabled: true,
                loyaltyEarnPointsPerUnit: 5,
                prepaidPaymentsEnabled: true)
            _ = try await APITestHelpers.request(
                app, .PUT, "/api/auth/config", token: adminToken, body: cfg)

            let menuRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Free Latte",
                    priceCents: 500,
                    isAvailable: true,
                    loyaltyRedeemPoints: 50))
            let menu = try APITestHelpers.decodeBody(MenuItem.self, from: menuRes)

            struct Enroll: Content { let userId: String }
            struct Accrue: Content { let userId: String; let points: Int }
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/enroll",
                token: adminToken, body: Enroll(userId: user.id))
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/accrue",
                token: adminToken, body: Accrue(userId: user.id, points: 100))

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup,
                    useLoyaltyPoints: true))
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            #expect(session.amountCents == 0)
            #expect(session.paymentIntentId == nil)

            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .ok)
            let order = try APITestHelpers.decodeBody(Order.self, from: confirmRes)
            #expect(order.paymentStatus == .waived)
            #expect(order.totalCents == 0)
            _ = cfg
        }
        try await APITestHelpers.shutdownApp(app)
    }

    // MARK: - Stripe Tax

    @Test func prepareAppliesStripeTaxToChargeAmount() async throws {
        let adminEmail = "pay-tax-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            await app.fakeStripe?.setTaxPercent(10)
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-tax-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 1000)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            #expect(session.quote.totalCents == 1000)
            #expect(session.quote.taxCents == 100)
            #expect(session.amountCents == 1100)
            #expect(await app.fakeStripe?.lastPaymentIntentAmount == 1100)
            #expect(await app.fakeStripe?.lastTaxCalculationId != nil)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func confirmWithTaxPersistsOrderTotalAndRecordsTaxTransaction() async throws {
        let adminEmail = "pay-tax-fulfill-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            await app.fakeStripe?.setTaxPercent(10)
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-tax-fulfill-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 1000)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    customerName: "Tax Guest",
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            let piId = try #require(session.paymentIntentId)
            let taxCalcId = try #require(await app.fakeStripe?.lastTaxCalculationId)
            await app.fakeStripe?.markSucceeded(piId)

            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .ok)
            let order = try APITestHelpers.decodeBody(Order.self, from: confirmRes)
            #expect(order.paymentStatus == .paid)
            #expect(order.totalCents == 1100)
            let txns = await app.fakeStripe?.taxTransactions ?? []
            #expect(txns.contains("\(taxCalcId):\(order.id)"))
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func prepareSkipsTaxWhenStripeTaxDisabled() async throws {
        let adminEmail = "pay-tax-off-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail) { _ in
            APITestHelpers.enableFakePaymentsEnv()
            setenv("STRIPE_TAX_ENABLED", "0", 1)
        }
        do {
            await app.fakeStripe?.setTaxPercent(10)
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-tax-off-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 1000)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            #expect(session.quote.totalCents == 1000)
            #expect((session.quote.taxCents ?? 0) == 0)
            #expect(session.amountCents == 1000)
            #expect(await app.fakeStripe?.lastTaxCalculationId == nil)
            #expect(await app.fakeStripe?.lastPaymentIntentAmount == 1000)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func prepareChargesMerchandiseOnlyWhenTaxCalculationFails() async throws {
        let adminEmail = "pay-tax-fail-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            await app.fakeStripe?.setTaxPercent(10)
            await app.fakeStripe?.setTaxShouldFail(true)
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-tax-fail-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 1000)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            #expect(prepRes.status == .ok)
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            #expect(session.quote.totalCents == 1000)
            #expect(session.quote.taxCents == 0)
            #expect(session.amountCents == 1000)
            #expect(await app.fakeStripe?.lastPaymentIntentAmount == 1000)
            #expect(await app.fakeStripe?.lastTaxCalculationId == nil)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func fulfillFailureRefundsPaymentIntent() async throws {
        let adminEmail = "pay-refund-admin@example.com"
        let app = try await makePaymentsApp(adminEmail: adminEmail)
        do {
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "pay-refund-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            try await enableMerchantPrepaid(app: app, adminToken: adminToken)
            let menu = try await seedMenu(app: app, adminToken: adminToken, priceCents: 400)

            let prepRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/prepare",
                token: userToken,
                body: CreateCheckoutSessionRequest(
                    items: [OrderItem(menuItemId: menu.id, quantity: 1)],
                    channel: .pickup))
            let session = try APITestHelpers.decodeBody(CheckoutSessionResponse.self, from: prepRes)
            let piId = try #require(session.paymentIntentId)
            await app.fakeStripe?.markSucceeded(piId)

            // Corrupt frozen quote so fulfill fails after PI succeeded.
            var stored = try #require(try await app.mongoStore.findCheckoutSession(by: session.sessionId))
            stored.quote.totalCents = 99999
            _ = try await app.mongoStore.update(checkoutSession: stored)

            let confirmRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/checkout/confirm",
                token: userToken,
                body: ConfirmCheckoutRequest(sessionId: session.sessionId))
            #expect(confirmRes.status == .conflict)
            let refunded = await app.fakeStripe?.refunded ?? []
            #expect(refunded.contains(piId))
            let after = try await app.mongoStore.findCheckoutSession(by: session.sessionId)
            #expect(after?.status == .failed)
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

//
//  StripeClientPort.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

struct StripePaymentIntentSnapshot: Sendable, Equatable {
    var id: String
    var clientSecret: String?
    var status: String
    var amount: Int
    var currency: String
    var metadata: [String: String]
}

protocol StripeClientPort: Sendable {
    func ensureCustomer(userId: String, email: String, existingCustomerId: String?) async throws -> String
    func createEphemeralKey(customerId: String) async throws -> String
    func createTaxCalculation(
        currency: String,
        amountCents: Int,
        reference: String,
        taxCode: String?,
        address: StripeTaxAddress?,
        customerIP: String?
    ) async throws -> StripeTaxCalculation
    func createPaymentIntent(
        amountCents: Int,
        currency: String,
        customerId: String,
        metadata: [String: String],
        taxCalculationId: String?
    ) async throws -> StripePaymentIntentSnapshot
    func retrievePaymentIntent(id: String) async throws -> StripePaymentIntentSnapshot
    func refundPaymentIntent(id: String) async throws
    func cancelPaymentIntent(id: String) async throws
    func createTaxTransaction(fromCalculationId calculationId: String, reference: String) async throws
}

/// In-memory Stripe for tests — no network.
actor FakeStripeClient: StripeClientPort {
    private var customers: [String: String] = [:]
    private var intents: [String: StripePaymentIntentSnapshot] = [:]
    private var calculations: [String: StripeTaxCalculation] = [:]
    var nextIntentStatus: String = "requires_payment_method"
    var forceSucceedOnCreate: Bool = false
    /// When > 0, createTaxCalculation adds this percent (e.g. 10 = 10%).
    var taxPercent: Int = 0
    /// When true, createTaxCalculation throws (exercise prepare soft-fail).
    var taxShouldFail: Bool = false
    private(set) var refunded: [String] = []
    private(set) var taxTransactions: [String] = []
    private(set) var lastPaymentIntentAmount: Int?
    private(set) var lastTaxCalculationId: String?

    func ensureCustomer(userId: String, email: String, existingCustomerId: String?) async throws -> String {
        if let existingCustomerId, !existingCustomerId.isEmpty { return existingCustomerId }
        if let id = customers[userId] { return id }
        let id = "cus_fake_\(userId.prefix(8))"
        customers[userId] = id
        return id
    }

    func createEphemeralKey(customerId: String) async throws -> String {
        "ek_fake_\(customerId)"
    }

    func createTaxCalculation(
        currency: String,
        amountCents: Int,
        reference: String,
        taxCode: String?,
        address: StripeTaxAddress?,
        customerIP: String?
    ) async throws -> StripeTaxCalculation {
        _ = reference
        _ = taxCode
        _ = address
        _ = customerIP
        if taxShouldFail {
            throw Abort(.badGateway, reason: "Fake Stripe Tax failure")
        }
        let tax = max(0, amountCents * taxPercent / 100)
        let id = "taxcalc_fake_\(UUID().uuidString.prefix(8))"
        let calc = StripeTaxCalculation(
            id: id,
            amountTotal: amountCents + tax,
            taxAmountExclusive: tax,
            currency: currency)
        calculations[id] = calc
        lastTaxCalculationId = id
        return calc
    }

    func createPaymentIntent(
        amountCents: Int,
        currency: String,
        customerId: String,
        metadata: [String: String],
        taxCalculationId: String?
    ) async throws -> StripePaymentIntentSnapshot {
        _ = taxCalculationId
        let id = "pi_fake_\(UUID().uuidString.prefix(8))"
        let status = forceSucceedOnCreate ? "succeeded" : nextIntentStatus
        let snap = StripePaymentIntentSnapshot(
            id: id,
            clientSecret: "\(id)_secret_fake",
            status: status,
            amount: amountCents,
            currency: currency,
            metadata: metadata)
        intents[id] = snap
        lastPaymentIntentAmount = amountCents
        return snap
    }

    func retrievePaymentIntent(id: String) async throws -> StripePaymentIntentSnapshot {
        guard let snap = intents[id] else {
            throw Abort(.notFound, reason: "Unknown PaymentIntent \(id)")
        }
        return snap
    }

    func refundPaymentIntent(id: String) async throws {
        refunded.append(id)
    }

    func cancelPaymentIntent(id: String) async throws {
        guard var snap = intents[id] else { return }
        snap.status = "canceled"
        intents[id] = snap
    }

    func createTaxTransaction(fromCalculationId calculationId: String, reference: String) async throws {
        guard calculations[calculationId] != nil else {
            throw Abort(.badRequest, reason: "Unknown tax calculation")
        }
        taxTransactions.append("\(calculationId):\(reference)")
    }

    func markSucceeded(_ id: String) {
        guard var snap = intents[id] else { return }
        snap.status = "succeeded"
        intents[id] = snap
    }

    func setTaxPercent(_ percent: Int) {
        taxPercent = max(0, percent)
    }

    func setTaxShouldFail(_ fail: Bool) {
        taxShouldFail = fail
    }
}

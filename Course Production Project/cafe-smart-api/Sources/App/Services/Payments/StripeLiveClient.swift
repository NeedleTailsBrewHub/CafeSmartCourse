//
//  StripeLiveClient.swift
//  CafeSmartAPI
//
//  Thin Stripe REST adapter (PaymentIntents / Customers / EphemeralKeys).
//  Kept behind StripeClientPort so tests use FakeStripeClient.
//

import Foundation
import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct StripeLiveClient: StripeClientPort {
    let secretKey: String
    let httpClient: any StripeHTTPPerforming
    /// Must match the mobile Stripe SDK API version (skip-stripe / stripe-ios).
    let ephemeralKeyAPIVersion: String

    init(
        secretKey: String,
        httpClient: any StripeHTTPPerforming = URLSessionStripeHTTP(),
        ephemeralKeyAPIVersion: String = PaymentsPolicy.stripeEphemeralKeyAPIVersion
    ) {
        self.secretKey = secretKey
        self.httpClient = httpClient
        self.ephemeralKeyAPIVersion = ephemeralKeyAPIVersion
    }

    func ensureCustomer(userId: String, email: String, existingCustomerId: String?) async throws
        -> String
    {
        if let existingCustomerId, !existingCustomerId.isEmpty { return existingCustomerId }
        let body: [String: String] = [
            "email": email,
            "metadata[userId]": userId,
        ]
        let json = try await httpClient.postForm(
            path: "customers",
            secretKey: secretKey,
            fields: body,
            stripeVersion: nil,
            idempotencyKey: "cus_\(userId)")
        guard let id = json["id"] as? String else {
            throw Abort(.badGateway, reason: "Stripe customer create failed")
        }
        return id
    }

    func createEphemeralKey(customerId: String) async throws -> String {
        let json = try await httpClient.postForm(
            path: "ephemeral_keys",
            secretKey: secretKey,
            fields: ["customer": customerId],
            stripeVersion: ephemeralKeyAPIVersion,
            idempotencyKey: nil)
        guard let secret = json["secret"] as? String else {
            throw Abort(.badGateway, reason: "Stripe ephemeral key failed")
        }
        return secret
    }

    func createTaxCalculation(
        currency: String,
        amountCents: Int,
        reference: String,
        taxCode: String?,
        address: StripeTaxAddress?,
        customerIP: String?
    ) async throws -> StripeTaxCalculation {
        var fields: [String: String] = [
            "currency": currency,
            "line_items[0][amount]": "\(amountCents)",
            "line_items[0][reference]": String(reference.prefix(500)),
            "line_items[0][tax_behavior]": "exclusive",
        ]
        if let taxCode, !taxCode.isEmpty {
            fields["line_items[0][tax_code]"] = taxCode
        }
        if let address {
            fields["customer_details[address][country]"] = address.country
            if let line1 = address.line1, !line1.isEmpty {
                fields["customer_details[address][line1]"] = line1
            }
            if let city = address.city, !city.isEmpty {
                fields["customer_details[address][city]"] = city
            }
            if let state = address.state, !state.isEmpty {
                fields["customer_details[address][state]"] = state
            }
            if let postal = address.postalCode, !postal.isEmpty {
                fields["customer_details[address][postal_code]"] = postal
            }
            fields["customer_details[address_source]"] = "shipping"
        } else if let customerIP, !customerIP.isEmpty {
            fields["customer_details[ip_address]"] = customerIP
        } else {
            throw Abort(
                .badRequest,
                reason: "Stripe Tax needs STRIPE_TAX_ADDRESS_* or client IP")
        }
        let json = try await httpClient.postForm(
            path: "tax/calculations",
            secretKey: secretKey,
            fields: fields,
            stripeVersion: nil,
            idempotencyKey: "tax_\(reference)")
        guard let id = json["id"] as? String,
            let amountTotal = Self.intValue(json["amount_total"]),
            let currencyOut = json["currency"] as? String
        else {
            throw Abort(.badGateway, reason: "Invalid Tax Calculation payload")
        }
        let exclusive = Self.intValue(json["tax_amount_exclusive"]) ?? 0
        return StripeTaxCalculation(
            id: id,
            amountTotal: amountTotal,
            taxAmountExclusive: exclusive,
            currency: currencyOut)
    }

    func createPaymentIntent(
        amountCents: Int,
        currency: String,
        customerId: String,
        metadata: [String: String],
        taxCalculationId: String?
    ) async throws -> StripePaymentIntentSnapshot {
        var fields: [String: String] = [
            "amount": "\(amountCents)",
            "currency": currency,
            "customer": customerId,
            "automatic_payment_methods[enabled]": "true",
            // Native PaymentSheet — avoid redirect-based methods that leave the app.
            "automatic_payment_methods[allow_redirects]": "never",
        ]
        for (k, v) in metadata {
            fields["metadata[\(k)]"] = v
        }
        // Newer API accounts: auto-commit tax on PI success.
        if let taxCalculationId, !taxCalculationId.isEmpty {
            fields["hooks[inputs][tax][calculation]"] = taxCalculationId
        }
        let idem =
            metadata["checkoutSessionId"].map { "pi_\($0)" }
            ?? "pi_\(UUID().uuidString)"
        do {
            let json = try await httpClient.postForm(
                path: "payment_intents",
                secretKey: secretKey,
                fields: fields,
                stripeVersion: nil,
                idempotencyKey: idem)
            return try Self.parseIntent(json)
        } catch {
            // Older API versions reject `hooks` — retry without and commit tax on fulfill.
            guard fields["hooks[inputs][tax][calculation]"] != nil else { throw error }
            fields.removeValue(forKey: "hooks[inputs][tax][calculation]")
            let json = try await httpClient.postForm(
                path: "payment_intents",
                secretKey: secretKey,
                fields: fields,
                stripeVersion: nil,
                idempotencyKey: "\(idem)_notaxhook")
            return try Self.parseIntent(json)
        }
    }

    func retrievePaymentIntent(id: String) async throws -> StripePaymentIntentSnapshot {
        let json = try await httpClient.getJSON(path: "payment_intents/\(id)", secretKey: secretKey)
        return try Self.parseIntent(json)
    }

    func refundPaymentIntent(id: String) async throws {
        _ = try await httpClient.postForm(
            path: "refunds",
            secretKey: secretKey,
            fields: ["payment_intent": id],
            stripeVersion: nil,
            idempotencyKey: "rf_\(id)")
    }

    func cancelPaymentIntent(id: String) async throws {
        _ = try await httpClient.postForm(
            path: "payment_intents/\(id)/cancel",
            secretKey: secretKey,
            fields: [:],
            stripeVersion: nil,
            idempotencyKey: "cancel_\(id)")
    }

    func createTaxTransaction(fromCalculationId calculationId: String, reference: String) async throws {
        _ = try await httpClient.postForm(
            path: "tax/transactions/create_from_calculation",
            secretKey: secretKey,
            fields: [
                "calculation": calculationId,
                "reference": String(reference.prefix(500)),
            ],
            stripeVersion: nil,
            idempotencyKey: "tax_tx_\(reference)")
    }

    private static func parseIntent(_ json: [String: Any]) throws -> StripePaymentIntentSnapshot {
        guard let id = json["id"] as? String,
            let status = json["status"] as? String,
            let amount = intValue(json["amount"]),
            let currency = json["currency"] as? String
        else {
            throw Abort(.badGateway, reason: "Invalid PaymentIntent payload")
        }
        var meta: [String: String] = [:]
        if let m = json["metadata"] as? [String: Any] {
            for (k, v) in m {
                if let s = v as? String {
                    meta[k] = s
                } else if let n = v as? NSNumber {
                    meta[k] = n.stringValue
                }
            }
        }
        return StripePaymentIntentSnapshot(
            id: id,
            clientSecret: json["client_secret"] as? String,
            status: status,
            amount: amount,
            currency: currency,
            metadata: meta)
    }

    /// JSONSerialization often yields NSNumber / Int64 / Double for Stripe amounts.
    fileprivate static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let i as Int64: return Int(i)
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        case let s as String: return Int(s)
        default: return nil
        }
    }
}

protocol StripeHTTPPerforming: Sendable {
    func postForm(
        path: String,
        secretKey: String,
        fields: [String: String],
        stripeVersion: String?,
        idempotencyKey: String?
    ) async throws -> [String: Any]
    func getJSON(path: String, secretKey: String) async throws -> [String: Any]
}

struct URLSessionStripeHTTP: StripeHTTPPerforming {
    func postForm(
        path: String,
        secretKey: String,
        fields: [String: String],
        stripeVersion: String?,
        idempotencyKey: String?
    ) async throws -> [String: Any] {
        var comps: [String] = []
        for (k, v) in fields {
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            comps.append("\(ek)=\(ev)")
        }
        var req = URLRequest(url: URL(string: "https://api.stripe.com/v1/\(path)")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let stripeVersion {
            req.setValue(stripeVersion, forHTTPHeaderField: "Stripe-Version")
        }
        if let idempotencyKey {
            req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        req.httpBody = comps.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Abort(.badGateway, reason: "Stripe HTTP error on POST \(path)")
        }
        guard (200...299).contains(http.statusCode) else {
            let stripeCode = Self.stripeErrorCode(from: data)
            throw Abort(
                .badGateway,
                reason: "Stripe HTTP \(http.statusCode) on POST \(path)"
                    + (stripeCode.map { " (\($0))" } ?? ""))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Abort(.badGateway, reason: "Stripe JSON decode failed")
        }
        return json
    }

    func getJSON(path: String, secretKey: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.stripe.com/v1/\(path)")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Abort(.badGateway, reason: "Stripe HTTP error on GET \(path)")
        }
        guard (200...299).contains(http.statusCode) else {
            let stripeCode = Self.stripeErrorCode(from: data)
            throw Abort(
                .badGateway,
                reason: "Stripe HTTP \(http.statusCode) on GET \(path)"
                    + (stripeCode.map { " (\($0))" } ?? ""))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Abort(.badGateway, reason: "Stripe JSON decode failed")
        }
        return json
    }

    /// Extract Stripe error `code` only — never log full bodies (may contain PII).
    private static func stripeErrorCode(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let err = json["error"] as? [String: Any],
            let code = err["code"] as? String
        else { return nil }
        return code
    }
}

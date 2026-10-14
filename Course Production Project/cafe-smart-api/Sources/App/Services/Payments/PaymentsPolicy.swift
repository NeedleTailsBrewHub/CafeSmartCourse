//
//  PaymentsPolicy.swift
//  CafeSmartAPI
//

import Vapor

enum PaymentsPolicy {
    static var paymentsEnabledEnv: Bool {
        guard let raw = Environment.get("PAYMENTS_ENABLED")?.lowercased() else { return false }
        return raw == "1" || raw == "true" || raw == "yes"
    }

    static var stripeSecretKey: String? {
        let v = Environment.get("STRIPE_SECRET_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    static var stripePublishableKey: String? {
        let v = Environment.get("STRIPE_PUBLISHABLE_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    static var stripeWebhookSecret: String? {
        let v = Environment.get("STRIPE_WEBHOOK_SECRET")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    static var currency: String {
        (Environment.get("STRIPE_CURRENCY") ?? "usd").lowercased()
    }

    static var merchantCountry: String {
        (Environment.get("STRIPE_MERCHANT_COUNTRY") ?? "US").uppercased()
    }

    /// Pin to stripe-ios / skip-stripe SDK version (PaymentSheet ephemeral keys).
    static var stripeEphemeralKeyAPIVersion: String {
        Environment.get("STRIPE_EPHEMERAL_KEY_API_VERSION") ?? "2020-08-27"
    }

    /// When true (default), prepaid prepare runs Stripe Tax Calculations and charges amount_total.
    static var stripeTaxEnabled: Bool {
        guard let raw = Environment.get("STRIPE_TAX_ENABLED")?.lowercased() else { return true }
        return raw == "1" || raw == "true" || raw == "yes"
    }

    /// Optional override; empty → Stripe Tax Settings default product tax code.
    static var stripeTaxCode: String? {
        let v = Environment.get("STRIPE_TAX_CODE")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    /// Café / pickup location for Stripe Tax (origin-style for in-store pickup).
    static var stripeTaxAddress: StripeTaxAddress? {
        let country = (Environment.get("STRIPE_TAX_ADDRESS_COUNTRY") ?? merchantCountry)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard country.count == 2 else { return nil }
        let line1 = Environment.get("STRIPE_TAX_ADDRESS_LINE1")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let city = Environment.get("STRIPE_TAX_ADDRESS_CITY")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let state = Environment.get("STRIPE_TAX_ADDRESS_STATE")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let postal = Environment.get("STRIPE_TAX_ADDRESS_POSTAL_CODE")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // US requires postal; other countries need at least country.
        if country == "US", postal?.isEmpty != false { return nil }
        return StripeTaxAddress(
            line1: line1,
            city: city,
            state: state,
            postalCode: postal,
            country: country)
    }

    /// Ops + keys present — Stripe can run even if merchant has not toggled yet.
    /// Webhook secret is required so Dashboard delivery is not half-wired in production.
    static var prepaidAvailable: Bool {
        paymentsEnabledEnv
            && stripeSecretKey != nil
            && stripePublishableKey != nil
            && stripeWebhookSecret != nil
    }

    static func prepaidEnabled(config: BusinessConfig?) -> Bool {
        prepaidAvailable && (config?.prepaidPaymentsEnabled == true)
    }

    /// Default on — merchant must set `payAtPickupEnabled = false` to require prepaid.
    static func payAtPickupEnabled(config: BusinessConfig?) -> Bool {
        config?.isPayAtPickupEnabled ?? true
    }

    static func capabilities(config: BusinessConfig?) -> CheckoutCapabilities {
        CheckoutCapabilities(
            prepaidAvailable: prepaidAvailable,
            prepaidEnabled: prepaidEnabled(config: config),
            currency: currency,
            merchantCountry: merchantCountry,
            payAtPickupEnabled: payAtPickupEnabled(config: config))
    }
}

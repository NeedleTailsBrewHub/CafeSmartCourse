//
//  CheckoutPaymentCoordinator.swift
//  CafeSmart
//
//  Pure checkout payment state helpers (unit-tested; no network / no Stripe UI).
//

#if SKIP
import SkipFoundation
#else
import Foundation
import VenueSmartKit
#endif

public enum CheckoutPaymentPhase: Equatable, Sendable {
    case idle
    case preparing
    case readyForSheet
    case confirming
    case done
    case failed
}

/// Fields required to build skip-stripe `StripePaymentConfiguration`.
public struct StripeSheetConfigFields: Equatable, Sendable {
    public var publishableKey: String
    public var merchantName: String
    public var customerID: String
    public var ephemeralKeySecret: String
    public var clientSecret: String
    public var sessionId: String
    public var amountCents: Int
}

public enum CheckoutPaymentCoordinator {
    /// Mac never shows Pay now (skip-stripe is mobile PaymentSheet).
    public static func showsPayNow(prepaidEnabled: Bool, isMac: Bool) -> Bool {
        prepaidEnabled && !isMac
    }

    /// Merchant can disable counter / in-person pay (default on).
    public static func showsPayAtPickup(payAtPickupEnabled: Bool) -> Bool {
        payAtPickupEnabled
    }

    public static func shouldSkipPaymentSheet(amountCents: Int) -> Bool {
        amountCents <= 0
    }

    /// Map prepare response → sheet config. Returns nil when $0 (no PI / skip sheet).
    public static func sheetConfig(
        from response: CheckoutSessionResponse,
        merchantName: String = "CafeSmart"
    ) -> StripeSheetConfigFields? {
        if shouldSkipPaymentSheet(amountCents: response.amountCents) {
            return nil
        }
        guard
            let customerID = response.customerId,
            let ephemeralKeySecret = response.ephemeralKeySecret,
            let clientSecret = response.paymentIntentClientSecret,
            !customerID.isEmpty,
            !ephemeralKeySecret.isEmpty,
            !clientSecret.isEmpty
        else {
            return nil
        }
        return StripeSheetConfigFields(
            publishableKey: response.publishableKey,
            merchantName: merchantName,
            customerID: customerID,
            ephemeralKeySecret: ephemeralKeySecret,
            clientSecret: clientSecret,
            sessionId: response.sessionId,
            amountCents: response.amountCents)
    }

    public static func phaseAfterPrepare(
        response: CheckoutSessionResponse
    ) -> CheckoutPaymentPhase {
        if shouldSkipPaymentSheet(amountCents: response.amountCents) {
            return .confirming
        }
        if sheetConfig(from: response) != nil {
            return .readyForSheet
        }
        return .failed
    }
}

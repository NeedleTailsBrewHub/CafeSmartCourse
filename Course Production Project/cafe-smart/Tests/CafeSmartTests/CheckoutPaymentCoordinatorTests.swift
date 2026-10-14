//
//  CheckoutPaymentCoordinatorTests.swift
//  CafeSmartTests
//

import Foundation
import Testing
import VenueSmartKit
@testable import CafeSmart

@Suite("Checkout payment coordinator")
struct CheckoutPaymentCoordinatorTests {

    @Test func hidesPayNowWhenPrepaidDisabled() {
        #expect(
            !CheckoutPaymentCoordinator.showsPayNow(prepaidEnabled: false, isMac: false))
    }

    @Test func hidesPayNowOnMacEvenWhenEnabled() {
        #expect(
            !CheckoutPaymentCoordinator.showsPayNow(prepaidEnabled: true, isMac: true))
    }

    @Test func showsPayNowOnMobileWhenEnabled() {
        #expect(
            CheckoutPaymentCoordinator.showsPayNow(prepaidEnabled: true, isMac: false))
    }

    @Test func showsPayAtPickupByDefault() {
        #expect(CheckoutPaymentCoordinator.showsPayAtPickup(payAtPickupEnabled: true))
    }

    @Test func hidesPayAtPickupWhenMerchantDisables() {
        #expect(!CheckoutPaymentCoordinator.showsPayAtPickup(payAtPickupEnabled: false))
    }

    @Test func zeroAmountSkipsSheetAndGoesToConfirming() {
        let response = CheckoutSessionResponse(
            sessionId: "sess1",
            publishableKey: "pk_test",
            customerId: nil,
            ephemeralKeySecret: nil,
            paymentIntentClientSecret: nil,
            paymentIntentId: nil,
            amountCents: 0,
            currency: "usd",
            quote: CheckoutQuote(
                subtotalCents: 500,
                loyaltyDiscountCents: 500,
                totalCents: 0,
                loyaltyPointsSpent: 50,
                loyaltyPointsEarned: 0),
            expiresAt: Date())
        #expect(CheckoutPaymentCoordinator.shouldSkipPaymentSheet(amountCents: 0))
        #expect(CheckoutPaymentCoordinator.sheetConfig(from: response) == nil)
        #expect(CheckoutPaymentCoordinator.phaseAfterPrepare(response: response) == .confirming)
    }

    @Test func mapsSheetConfigFromPrepareResponse() {
        let response = CheckoutSessionResponse(
            sessionId: "sess2",
            publishableKey: "pk_test",
            customerId: "cus_1",
            ephemeralKeySecret: "ek_1",
            paymentIntentClientSecret: "pi_1_secret",
            paymentIntentId: "pi_1",
            amountCents: 450,
            currency: "usd",
            quote: CheckoutQuote(
                subtotalCents: 450,
                loyaltyDiscountCents: 0,
                totalCents: 450,
                loyaltyPointsSpent: 0,
                loyaltyPointsEarned: 5),
            expiresAt: Date())
        let fields = CheckoutPaymentCoordinator.sheetConfig(from: response)
        #expect(fields?.publishableKey == "pk_test")
        #expect(fields?.customerID == "cus_1")
        #expect(fields?.ephemeralKeySecret == "ek_1")
        #expect(fields?.clientSecret == "pi_1_secret")
        #expect(fields?.sessionId == "sess2")
        #expect(fields?.amountCents == 450)
        #expect(CheckoutPaymentCoordinator.phaseAfterPrepare(response: response) == .readyForSheet)
    }

    @Test func missingSecretsFailsPhase() {
        let response = CheckoutSessionResponse(
            sessionId: "sess3",
            publishableKey: "pk_test",
            customerId: nil,
            ephemeralKeySecret: nil,
            paymentIntentClientSecret: nil,
            paymentIntentId: "pi_x",
            amountCents: 100,
            currency: "usd",
            quote: CheckoutQuote(
                subtotalCents: 100,
                loyaltyDiscountCents: 0,
                totalCents: 100,
                loyaltyPointsSpent: 0,
                loyaltyPointsEarned: 0),
            expiresAt: Date())
        #expect(CheckoutPaymentCoordinator.phaseAfterPrepare(response: response) == .failed)
    }
}

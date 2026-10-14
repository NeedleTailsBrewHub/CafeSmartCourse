//
//  PaymentModels.swift
//  CafeSmartAPI
//
//  Checkout / prepaid payment wire types (BinaryCodable mirrored on client).
//

import Foundation
import Vapor

public enum OrderPaymentStatus: String, Codable, Sendable, Equatable, Content {
    case unpaid
    case paid
    case waived
}

public enum OrderPaymentMode: String, Codable, Sendable, Equatable, Content {
    case payAtPickup
    case prepaid
}

public enum CheckoutSessionStatus: String, Codable, Sendable, Equatable {
    case pending
    /// Atomic claim while placeOrder runs (confirm + webhook race guard).
    case fulfilling
    case fulfilled
    case expired
    case failed
}

public struct CheckoutQuote: Content, Sendable, Equatable {
    public var subtotalCents: Int
    public var loyaltyDiscountCents: Int
    /// Merchandise total after loyalty (pre-tax).
    public var totalCents: Int
    public var loyaltyPointsSpent: Int
    public var loyaltyPointsEarned: Int
    /// Stripe Tax exclusive tax for prepaid; nil/0 when tax off or $0.
    public var taxCents: Int? = nil

    public var amountDueCents: Int { totalCents + max(0, taxCents ?? 0) }

    public init(
        subtotalCents: Int,
        loyaltyDiscountCents: Int,
        totalCents: Int,
        loyaltyPointsSpent: Int,
        loyaltyPointsEarned: Int,
        taxCents: Int? = nil
    ) {
        self.subtotalCents = subtotalCents
        self.loyaltyDiscountCents = loyaltyDiscountCents
        self.totalCents = totalCents
        self.loyaltyPointsSpent = loyaltyPointsSpent
        self.loyaltyPointsEarned = loyaltyPointsEarned
        self.taxCents = taxCents
    }
}

public struct CreateCheckoutSessionRequest: Content, Sendable, Equatable {
    public var customerName: String?
    public var items: [OrderItem]
    public var pickupTime: Date?
    public var channel: Order.OrderChannel?
    public var serviceType: Order.ServiceType?
    public var tableId: String?
    public var guests: Int?
    public var reservationId: String?
    public var useLoyaltyPoints: Bool?

    public init(
        customerName: String? = nil,
        items: [OrderItem],
        pickupTime: Date? = nil,
        channel: Order.OrderChannel? = nil,
        serviceType: Order.ServiceType? = nil,
        tableId: String? = nil,
        guests: Int? = nil,
        reservationId: String? = nil,
        useLoyaltyPoints: Bool? = nil
    ) {
        self.customerName = customerName
        self.items = items
        self.pickupTime = pickupTime
        self.channel = channel
        self.serviceType = serviceType
        self.tableId = tableId
        self.guests = guests
        self.reservationId = reservationId
        self.useLoyaltyPoints = useLoyaltyPoints
    }
}

public struct CheckoutSessionResponse: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var sessionId: String
    public var publishableKey: String
    public var customerId: String?
    public var ephemeralKeySecret: String?
    public var paymentIntentClientSecret: String?
    public var paymentIntentId: String?
    public var amountCents: Int
    public var currency: String
    public var quote: CheckoutQuote
    public var expiresAt: Date

    public init(
        sessionId: String,
        publishableKey: String,
        customerId: String? = nil,
        ephemeralKeySecret: String? = nil,
        paymentIntentClientSecret: String? = nil,
        paymentIntentId: String? = nil,
        amountCents: Int,
        currency: String,
        quote: CheckoutQuote,
        expiresAt: Date
    ) {
        self.sessionId = sessionId
        self.publishableKey = publishableKey
        self.customerId = customerId
        self.ephemeralKeySecret = ephemeralKeySecret
        self.paymentIntentClientSecret = paymentIntentClientSecret
        self.paymentIntentId = paymentIntentId
        self.amountCents = amountCents
        self.currency = currency
        self.quote = quote
        self.expiresAt = expiresAt
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct ConfirmCheckoutRequest: Content, Sendable, Equatable {
    public var sessionId: String
    public init(sessionId: String) { self.sessionId = sessionId }
}

public struct CheckoutCapabilities: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var prepaidAvailable: Bool
    public var prepaidEnabled: Bool
    public var currency: String
    public var merchantCountry: String
    /// Pay at counter / in person. Default true when omitted on older payloads.
    public var payAtPickupEnabled: Bool? = nil

    public init(
        prepaidAvailable: Bool,
        prepaidEnabled: Bool,
        currency: String,
        merchantCountry: String,
        payAtPickupEnabled: Bool = true
    ) {
        self.prepaidAvailable = prepaidAvailable
        self.prepaidEnabled = prepaidEnabled
        self.currency = currency
        self.merchantCountry = merchantCountry
        self.payAtPickupEnabled = payAtPickupEnabled
    }

    public var isPayAtPickupEnabled: Bool { payAtPickupEnabled != false }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Persisted prepare snapshot — order is placed from this, not a re-posted cart.
public struct CheckoutSession: Content, Sendable, Equatable {
    public var id: String
    public var userId: String
    public var customerName: String?
    public var items: [OrderItem]
    public var pickupTime: Date?
    public var channel: Order.OrderChannel?
    public var serviceType: Order.ServiceType?
    public var tableId: String?
    public var guests: Int?
    public var reservationId: String?
    public var useLoyaltyPoints: Bool
    public var quote: CheckoutQuote
    public var paymentIntentId: String?
    public var amountCents: Int
    public var currency: String
    public var status: CheckoutSessionStatus
    public var orderId: String?
    public var createdAt: Date
    public var expiresAt: Date
    /// Stripe Tax Calculation id linked for reporting on fulfill.
    public var taxCalculationId: String? = nil

    public init(
        id: String,
        userId: String,
        customerName: String? = nil,
        items: [OrderItem],
        pickupTime: Date? = nil,
        channel: Order.OrderChannel? = nil,
        serviceType: Order.ServiceType? = nil,
        tableId: String? = nil,
        guests: Int? = nil,
        reservationId: String? = nil,
        useLoyaltyPoints: Bool = false,
        quote: CheckoutQuote,
        paymentIntentId: String? = nil,
        amountCents: Int,
        currency: String,
        status: CheckoutSessionStatus = .pending,
        orderId: String? = nil,
        createdAt: Date = Date(),
        expiresAt: Date,
        taxCalculationId: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.customerName = customerName
        self.items = items
        self.pickupTime = pickupTime
        self.channel = channel
        self.serviceType = serviceType
        self.tableId = tableId
        self.guests = guests
        self.reservationId = reservationId
        self.useLoyaltyPoints = useLoyaltyPoints
        self.quote = quote
        self.paymentIntentId = paymentIntentId
        self.amountCents = amountCents
        self.currency = currency
        self.status = status
        self.orderId = orderId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.taxCalculationId = taxCalculationId
    }
}

//
//  Order.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is licensed under the MIT License.
//
//  See the LICENSE file for more information.
//
//  This file is part of the CafeSmartAPI Project

import Foundation
import Vapor

public enum OrderStatus: String, Codable, Sendable, Equatable {
	case pending
	case preparing
	case ready
	case completed
	case canceled
}

public struct OrderItem: Content, Sendable, Equatable {
	public var menuItemId: String
	/// Optional display name from client carts; ignored by inventory math.
	public var name: String?
	public var quantity: Int
	public var notes: String?
	/// Per-unit price charged (base + size). Falls back to menu price when nil.
	public var unitPriceCents: Int? = nil
	/// Typed size selection; server resolves surcharge from menu.sizeOptions (notes ignored for money).
	public var sizeName: String? = nil

	public init(
		menuItemId: String,
		name: String? = nil,
		quantity: Int,
		notes: String? = nil,
		unitPriceCents: Int? = nil,
		sizeName: String? = nil
	) {
		self.menuItemId = menuItemId
		self.name = name
		self.quantity = quantity
		self.notes = notes
		self.unitPriceCents = unitPriceCents
		self.sizeName = sizeName
	}
}

public struct Order: Content, Sendable, Equatable, BinaryResponseEncodable {
	public enum OrderChannel: String, Codable, Sendable, Equatable { case dineIn, takeaway, pickup, delivery }
	public enum ServiceType: String, Codable, Sendable, Equatable { case barista, kitchen, bakery }

	public var id: String
	public var status: OrderStatus
	public var customerName: String?
	/// Authenticated user who placed the order (optional for legacy/seed rows).
	public var customerUserId: String?
	public var items: [OrderItem]
	public var pickupTime: Date?
	public var channel: OrderChannel?
	public var serviceType: ServiceType?
	public var tableId: String?
	public var guests: Int?
	public var reservationId: String?
	public var createdAt: Date
	public var subtotalCents: Int? = nil
	public var loyaltyDiscountCents: Int? = nil
	public var totalCents: Int? = nil
	public var loyaltyPointsSpent: Int? = nil
	public var loyaltyPointsEarned: Int? = nil
	public var paymentStatus: OrderPaymentStatus? = nil
	public var stripePaymentIntentId: String? = nil
	public var checkoutSessionId: String? = nil
	public var paidAt: Date? = nil
	/// Prepaid Stripe Tax exclusive cents frozen at fulfill (nil for pay-at-pickup).
	public var taxCents: Int? = nil

	public init(
		id: String,
		status: OrderStatus,
		customerName: String? = nil,
		customerUserId: String? = nil,
		items: [OrderItem],
		pickupTime: Date? = nil,
		channel: OrderChannel? = nil,
		serviceType: ServiceType? = nil,
		tableId: String? = nil,
		guests: Int? = nil,
		reservationId: String? = nil,
		createdAt: Date,
		subtotalCents: Int? = nil,
		loyaltyDiscountCents: Int? = nil,
		totalCents: Int? = nil,
		loyaltyPointsSpent: Int? = nil,
		loyaltyPointsEarned: Int? = nil,
		paymentStatus: OrderPaymentStatus? = nil,
		stripePaymentIntentId: String? = nil,
		checkoutSessionId: String? = nil,
		paidAt: Date? = nil,
		taxCents: Int? = nil
	) {
		self.id = id
		self.status = status
		self.customerName = customerName
		self.customerUserId = customerUserId
		self.items = items
		self.pickupTime = pickupTime
		self.channel = channel
		self.serviceType = serviceType
		self.tableId = tableId
		self.guests = guests
		self.reservationId = reservationId
		self.createdAt = createdAt
		self.subtotalCents = subtotalCents
		self.loyaltyDiscountCents = loyaltyDiscountCents
		self.totalCents = totalCents
		self.loyaltyPointsSpent = loyaltyPointsSpent
		self.loyaltyPointsEarned = loyaltyPointsEarned
		self.paymentStatus = paymentStatus
		self.stripePaymentIntentId = stripePaymentIntentId
		self.checkoutSessionId = checkoutSessionId
		self.paidAt = paidAt
		self.taxCents = taxCents
	}

	public func encodeResponse(for request: Request) async throws -> Response {
		try binaryEncodedResponse()
	}
}

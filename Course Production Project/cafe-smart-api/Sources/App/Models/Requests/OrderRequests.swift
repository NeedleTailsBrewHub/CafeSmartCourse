//
//  OrderRequests.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 2025-08-19.
//

import Vapor

/// Wire name matches client `CreateOrderRequest` for BinaryCodable type headers.
public struct CreateOrderRequest: Content, Sendable {
	public var customerName: String?
	public var items: [OrderItem]
	public var pickupTime: Date?
	public var channel: Order.OrderChannel?
	public var serviceType: Order.ServiceType?
	public var tableId: String?
	public var guests: Int?
	public var reservationId: String?
	/// Guest must explicitly opt in; server ignores redemption unless true.
	public var useLoyaltyPoints: Bool? = nil
	/// Default pay-at-pickup. Prepaid must use `/checkout/confirm` — rejected here.
	public var paymentMode: OrderPaymentMode? = nil

	public init(
		customerName: String? = nil,
		items: [OrderItem],
		pickupTime: Date? = nil,
		channel: Order.OrderChannel? = nil,
		serviceType: Order.ServiceType? = nil,
		tableId: String? = nil,
		guests: Int? = nil,
		reservationId: String? = nil,
		useLoyaltyPoints: Bool? = nil,
		paymentMode: OrderPaymentMode? = nil
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
		self.paymentMode = paymentMode
	}
}

@available(*, deprecated, renamed: "CreateOrderRequest")
public typealias OrderCreateRequest = CreateOrderRequest

/// Wire name matches client `UpdateOrderStatusRequest` for BinaryCodable type headers.
public struct UpdateOrderStatusRequest: Content, Sendable {
	public var status: OrderStatus

	public init(status: OrderStatus) {
		self.status = status
	}
}

@available(*, deprecated, renamed: "UpdateOrderStatusRequest")
public typealias OrderStatusUpdateRequest = UpdateOrderStatusRequest

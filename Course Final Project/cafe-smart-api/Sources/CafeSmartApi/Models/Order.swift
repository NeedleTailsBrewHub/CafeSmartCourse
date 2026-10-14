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

    public init(menuItemId: String, name: String? = nil, quantity: Int, notes: String? = nil) {
        self.menuItemId = menuItemId
        self.name = name
        self.quantity = quantity
        self.notes = notes
    }
}

public struct Order: Content, Sendable, Equatable, BinaryResponseEncodable {
    public enum OrderChannel: String, Codable, Sendable, Equatable { case dineIn, takeaway, pickup, delivery }
    public enum ServiceType: String, Codable, Sendable, Equatable { case barista, kitchen, bakery }

    public var id: String
    public var status: OrderStatus
    public var customerName: String?
    public var items: [OrderItem]
    public var pickupTime: Date?
    public var channel: OrderChannel?
    public var serviceType: ServiceType?
    public var tableId: String?
    public var guests: Int?
    public var reservationId: String?
    public var createdAt: Date

    public init(
        id: String,
        status: OrderStatus,
        customerName: String? = nil,
        items: [OrderItem],
        pickupTime: Date? = nil,
        channel: OrderChannel? = nil,
        serviceType: ServiceType? = nil,
        tableId: String? = nil,
        guests: Int? = nil,
        reservationId: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.status = status
        self.customerName = customerName
        self.items = items
        self.pickupTime = pickupTime
        self.channel = channel
        self.serviceType = serviceType
        self.tableId = tableId
        self.guests = guests
        self.reservationId = reservationId
        self.createdAt = createdAt
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

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

    public init(
        customerName: String? = nil,
        items: [OrderItem],
        pickupTime: Date? = nil,
        channel: Order.OrderChannel? = nil,
        serviceType: Order.ServiceType? = nil,
        tableId: String? = nil,
        guests: Int? = nil,
        reservationId: String? = nil
    ) {
        self.customerName = customerName
        self.items = items
        self.pickupTime = pickupTime
        self.channel = channel
        self.serviceType = serviceType
        self.tableId = tableId
        self.guests = guests
        self.reservationId = reservationId
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


public struct OrdersWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [Order]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

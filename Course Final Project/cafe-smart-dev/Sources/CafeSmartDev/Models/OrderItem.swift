//
//  OrderItem.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/10/25.
//
#if SKIP
import SkipFoundation
#else
import Foundation
#endif

public enum OrderStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case pending, preparing, ready, completed, canceled
}

public struct OrderItem: Codable, Equatable, Sendable {
    public let menuItemId: String
    public let name: String?
    public let quantity: Int
    public let notes: String?

    public init(menuItemId: String, name: String? = nil, quantity: Int, notes: String? = nil) {
        self.menuItemId = menuItemId
        self.name = name
        self.quantity = quantity
        self.notes = notes
    }
}

public struct Order: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var status: OrderStatus
    public let customerName: String?
    public let items: [OrderItem]
    public let pickupTime: Date?
    public let createdAt: Date

    public enum OrderChannel: String, Codable, Sendable { case dineIn, takeaway, pickup, delivery }
    public enum ServiceType: String, Codable, Sendable { case barista, kitchen, bakery }

    // Additional optional fields for staffing and dine-in flow
    public var channel: OrderChannel? = nil
    public var serviceType: ServiceType? = nil
    public var tableId: String? = nil
    public var guests: Int? = nil
    public var reservationId: String? = nil

    public init(
        id: String,
        status: OrderStatus,
        customerName: String? = nil,
        items: [OrderItem],
        pickupTime: Date? = nil,
        createdAt: Date,
        channel: OrderChannel? = nil,
        serviceType: ServiceType? = nil,
        tableId: String? = nil,
        guests: Int? = nil,
        reservationId: String? = nil
    ) {
        self.id = id
        self.status = status
        self.customerName = customerName
        self.items = items
        self.pickupTime = pickupTime
        self.createdAt = createdAt
        self.channel = channel
        self.serviceType = serviceType
        self.tableId = tableId
        self.guests = guests
        self.reservationId = reservationId
    }
}




public struct OrdersWrapper: Codable, Sendable, Equatable {
    public let items: [Order]
}


public struct CreateOrderRequest: Codable, Sendable, Equatable {
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

public struct UpdateOrderStatusRequest: Codable, Sendable, Equatable {
    public var status: OrderStatus

    public init(status: OrderStatus) {
        self.status = status
    }
}


struct CartLine: Identifiable, Codable, Equatable {
    var id: String { item.id + "-" + String(sizeDeltaCents) }
    let item: MenuItem
    var quantity: Int
    let sizeDeltaCents: Int
    let sizeName: String?
    var unitCents: Int { item.priceCents + sizeDeltaCents }
    var lineCents: Int { unitCents * quantity }
}

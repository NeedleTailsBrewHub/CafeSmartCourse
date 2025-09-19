//
//  Order.swift
//  CafeSmart
//
//  Created by NeedleTails on 8/19/25
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmart Project
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



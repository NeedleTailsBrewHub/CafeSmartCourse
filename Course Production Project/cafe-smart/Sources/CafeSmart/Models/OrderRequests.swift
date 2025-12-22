//
//  OrderRequests.swift
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



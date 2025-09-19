//
//  CollectionModels.swift
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

import Foundation

public struct MenuItemsWrapper: Codable, Sendable, Equatable {
    public let items: [MenuItem]
}

public struct InventoryItemsWrapper: Codable, Sendable, Equatable {
    public let items: [InventoryItem]
}

public struct OrdersWrapper: Codable, Sendable, Equatable {
    public let items: [Order]
}

public struct ReservationsWrapper: Codable, Sendable, Equatable {
    public let items: [Reservation]
}



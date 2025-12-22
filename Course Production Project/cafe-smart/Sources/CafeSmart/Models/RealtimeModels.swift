//
//  RealtimeModels.swift
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

public enum MessagePacket: Codable, Sendable, Equatable {
    case order(OrderInfo)
    case inventory(InventoryInfo)
    case reservation(ReservationInfo)
    case modelUploaded(MLModelArtifact)
    case modelActivated(kind: PredictorKind, id: String)
    case modelDeleted(id: String)
    case predictorReady(kind: PredictorKind)
    case none
}

public enum OrderInfo: Codable, Sendable, Equatable {
    case created(Order)
    case updated(Order)
    case deleted(Order)
}

public enum InventoryInfo: Codable, Sendable, Equatable {
    case runningLow(InventoryItem)
    case restocked(InventoryItem)
    case outOfStock(InventoryItem)
    case reordered(InventoryItem)
}

public enum ReservationInfo: Codable, Sendable, Equatable {
    case created(Reservation)
    case updated(Reservation)
    case deleted(Reservation)
}



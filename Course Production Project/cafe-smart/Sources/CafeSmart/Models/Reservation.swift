//
//  Reservation.swift
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

public enum ReservationStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active, canceled, completed
}

public struct Reservation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let partySize: Int
    public let startTime: Date
    public let phone: String?
    public let notes: String?

    // Additional optional fields for capacity planning and flow
    public var durationMinutes: Int? = nil
    public var seatsOccupied: Int? = nil
    public var areaId: String? = nil
    public var tableId: String? = nil
    public var status: ReservationStatus? = nil
    public var specialOccasion: String? = nil
    public var internalNotes: String? = nil
    public var orderId: String? = nil

    public init(
        id: String,
        name: String,
        partySize: Int,
        startTime: Date,
        phone: String? = nil,
        notes: String? = nil,
        durationMinutes: Int? = nil,
        seatsOccupied: Int? = nil,
        areaId: String? = nil,
        tableId: String? = nil,
        status: ReservationStatus? = nil,
        specialOccasion: String? = nil,
        internalNotes: String? = nil,
        orderId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.partySize = partySize
        self.startTime = startTime
        self.phone = phone
        self.notes = notes
        self.durationMinutes = durationMinutes
        self.seatsOccupied = seatsOccupied
        self.areaId = areaId
        self.tableId = tableId
        self.status = status
        self.specialOccasion = specialOccasion
        self.internalNotes = internalNotes
        self.orderId = orderId
    }
}



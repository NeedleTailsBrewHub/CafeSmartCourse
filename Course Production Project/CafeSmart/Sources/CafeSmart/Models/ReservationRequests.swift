//
//  ReservationRequests.swift
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

public struct CreateReservationRequest: Codable, Sendable, Equatable {
    public var name: String
    public var partySize: Int
    public var startTime: Date
    public var phone: String?
    public var notes: String?
    // Optional
    public var durationMinutes: Int?
    public var seatsOccupied: Int?
    public var areaId: String?
    public var tableId: String?
    public var status: ReservationStatus?
    public var specialOccasion: String?
    public var internalNotes: String?
    public var orderId: String?

    public init(
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



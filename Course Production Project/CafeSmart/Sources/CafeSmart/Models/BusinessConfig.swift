//
//  BusinessConfig.swift
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

public struct BusinessHours: Codable, Sendable, Equatable {
    public let weekday: Int  // 1=Sun ... 7=Sat
    public let open: String  // "07:00"
    public let close: String // "20:00"

    public init(weekday: Int, open: String, close: String) {
        self.weekday = weekday
        self.open = open
        self.close = close
    }
}

public struct StaffingRules: Codable, Sendable, Equatable {
    public let ordersPerBaristaPerHour: Int
    public let ordersPerBakerPerHour: Int
    public let guestsPerHostPerHour: Int

    public init(
        ordersPerBaristaPerHour: Int,
        ordersPerBakerPerHour: Int,
        guestsPerHostPerHour: Int
    ) {
        self.ordersPerBaristaPerHour = ordersPerBaristaPerHour
        self.ordersPerBakerPerHour = ordersPerBakerPerHour
        self.guestsPerHostPerHour = guestsPerHostPerHour
    }
}

public struct BusinessConfig: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timezone: String
    public let hours: [BusinessHours]
    public let seatingCapacity: Int?
    public let staffing: StaffingRules

    public init(
        id: String,
        timezone: String,
        hours: [BusinessHours],
        seatingCapacity: Int?,
        staffing: StaffingRules
    ) {
        self.id = id
        self.timezone = timezone
        self.hours = hours
        self.seatingCapacity = seatingCapacity
        self.staffing = staffing
    }
}



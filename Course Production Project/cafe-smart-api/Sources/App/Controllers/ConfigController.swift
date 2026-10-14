//
//  ConfigController.swift
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

@preconcurrency import BSON
import Vapor

actor ConfigController {
    func runtime(req: Request) async throws -> ServerRuntime {
        ServerRuntime(demoMode: DemoModePolicy.isEnabled)
    }

    func get(req: Request) async throws -> BusinessConfig {
        if let cfg = try await req.store.getBusinessConfig() {
            return cfg
        }
        // First-run / empty DB — persist a usable default so admin UIs can load.
        let seeded = Self.makeDefaultConfig()
        return try await req.store.upsertBusinessConfig(seeded)
    }

    func upsert(req: Request) async throws -> BusinessConfig {
        var cfg = try req.content.decode(BusinessConfig.self)
        if cfg.reservationBooking == nil {
            cfg.reservationBooking = .default
        }
        // Keep a stable singleton id across admin saves.
        if let existing = try await req.store.getBusinessConfig() {
            cfg.id = existing.id
        } else if ObjectId(cfg.id) == nil {
            cfg.id = ObjectId().hexString
        }
        return try await req.store.upsertBusinessConfig(cfg)
    }

    private static func makeDefaultConfig() -> BusinessConfig {
        let hours: [BusinessHours] = (1...7).map { day in
            BusinessHours(weekday: day, open: "08:00", close: day == 5 || day == 6 ? "21:00" : "19:00")
        }
        var config = BusinessConfig(
            id: ObjectId().hexString,
            timezone: TimeZone.current.identifier,
            hours: hours,
            seatingCapacity: 40,
            staffing: StaffingRules(
                ordersPerBaristaPerHour: 40,
                ordersPerBakerPerHour: 25,
                guestsPerHostPerHour: 60)
        )
        config.loyaltyEnabled = false
        config.loyaltyEarnPointsPerUnit = 5
        config.reservationBooking = .default
        config.prepaidPaymentsEnabled = false
        config.payAtPickupEnabled = true
        return config
    }
}

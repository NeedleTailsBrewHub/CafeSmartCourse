//
//  Config.swift
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

import Vapor

public struct BusinessHours: Codable, Sendable, Equatable {
	public var weekday: Int
	public var open: String
	public var close: String
}

public struct StaffingRules: Codable, Sendable, Equatable {
	public var ordersPerBaristaPerHour: Int
	public var ordersPerBakerPerHour: Int
	public var guestsPerHostPerHour: Int
}

/// Admin-controlled reservation inventory and offered times.
public struct ReservationBookingSettings: Codable, Sendable, Equatable {
	/// When false, guests see no bookable slots.
	public var enabled: Bool
	/// How many tables may be reserved at once (concurrent inventory).
	public var tablesAvailable: Int
	/// Default seats per table when inventory is virtual (no seating map).
	public var defaultPartyCapacity: Int
	/// Spacing between offered starts when `slotStarts` is empty (15 / 30 / 60).
	public var slotIntervalMinutes: Int
	/// Held duration for each booking / turn time.
	public var turnMinutes: Int
	/// Explicit start times as `"HH:mm"`. Empty → generate from open hours + interval.
	public var slotStarts: [String]

	public init(
		enabled: Bool = true,
		tablesAvailable: Int = 8,
		defaultPartyCapacity: Int = 4,
		slotIntervalMinutes: Int = 30,
		turnMinutes: Int = 90,
		slotStarts: [String] = []
	) {
		self.enabled = enabled
		self.tablesAvailable = max(0, tablesAvailable)
		self.defaultPartyCapacity = max(1, defaultPartyCapacity)
		self.slotIntervalMinutes = max(5, slotIntervalMinutes)
		self.turnMinutes = max(15, turnMinutes)
		self.slotStarts = slotStarts
	}

	public static var `default`: ReservationBookingSettings { .init() }
}

public struct BusinessConfig: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var timezone: String
	public var hours: [BusinessHours]
	public var seatingCapacity: Int
	public var staffing: StaffingRules
	/// When false, earn/redeem at checkout is disabled (manual desk adjust still allowed).
	public var loyaltyEnabled: Bool? = nil
	/// Points awarded per paid unit when the menu item has earn enabled.
	public var loyaltyEarnPointsPerUnit: Int? = nil
	/// Admin reservation inventory + offered timeslots.
	public var reservationBooking: ReservationBookingSettings? = nil
	/// When true (and ops PAYMENTS_ENABLED + Stripe keys), in-app prepaid / wallets are offered.
	public var prepaidPaymentsEnabled: Bool? = nil
	/// When false, guests cannot place unpaid / pay-at-pickup orders. Default (nil) is on.
	public var payAtPickupEnabled: Bool? = nil

	public var isLoyaltyProgramEnabled: Bool { loyaltyEnabled == true }
	public var earnPointsPerUnit: Int { max(1, loyaltyEarnPointsPerUnit ?? 5) }
	public var bookingSettings: ReservationBookingSettings {
		reservationBooking ?? .default
	}
	public var isPayAtPickupEnabled: Bool { payAtPickupEnabled != false }
	public var isPrepaidPaymentsEnabled: Bool { prepaidPaymentsEnabled == true }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}



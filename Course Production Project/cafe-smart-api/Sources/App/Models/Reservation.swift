//
//  Reservation.swift
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

import Foundation
import Vapor

public enum ReservationStatus: String, Codable, Sendable, Equatable { case active, completed, canceled }

public struct Reservation: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var name: String
	public var partySize: Int
	public var startTime: Date
	public var phone: String?
	public var notes: String?
	public var durationMinutes: Int?
	public var seatsOccupied: Int?
	public var areaId: String?
	public var tableId: String?
	public var status: ReservationStatus?
	public var specialOccasion: String?
	public var internalNotes: String?
	public var orderId: String?
	/// Authenticated booker (optional for legacy/seed rows).
	public var customerUserId: String?

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
		orderId: String? = nil,
		customerUserId: String? = nil
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
		self.customerUserId = customerUserId
	}

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Wire name matches client `CreateReservationRequest`.
public struct CreateReservationRequest: Content, Sendable {
	public var name: String
	public var partySize: Int
	public var startTime: Date
	public var phone: String?
	public var notes: String?
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

public struct ReservationsWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [Reservation]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}



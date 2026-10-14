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
    public var areaId: String?
    public var tableId: String?
    public var status: ReservationStatus?

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct ReservationsWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [Reservation]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}



//
//  Seating.swift
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

public struct SeatingArea: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var id: String
    public var name: String
    public var defaultTurnMinutes: Int
    public var active: Bool

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

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

	public init(id: String, name: String, defaultTurnMinutes: Int, active: Bool) {
		self.id = id
		self.name = name
		self.defaultTurnMinutes = defaultTurnMinutes
		self.active = active
	}

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Wire name must match VenueSmartKit `CafeTable`.
public struct CafeTable: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var areaId: String
	public var name: String
	public var capacity: Int
	public var accessible: Bool
	public var highTop: Bool?
	public var outside: Bool?
	public var active: Bool

	public init(
		id: String,
		areaId: String,
		name: String,
		capacity: Int,
		accessible: Bool,
		highTop: Bool? = nil,
		outside: Bool? = nil,
		active: Bool
	) {
		self.id = id
		self.areaId = areaId
		self.name = name
		self.capacity = capacity
		self.accessible = accessible
		self.highTop = highTop
		self.outside = outside
		self.active = active
	}

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Internal alias — BinaryCodable wire identity is ``CafeTable``.
public typealias Table = CafeTable

/// Wire name matches client `CreateSeatingAreaRequest`.
public struct CreateSeatingAreaRequest: Content, Sendable {
	public var name: String
	public var defaultTurnMinutes: Int
	public var active: Bool

	public init(name: String, defaultTurnMinutes: Int, active: Bool = true) {
		self.name = name
		self.defaultTurnMinutes = defaultTurnMinutes
		self.active = active
	}
}

/// Wire name matches client `UpdateSeatingAreaRequest`.
public struct UpdateSeatingAreaRequest: Content, Sendable {
	public var name: String?
	public var defaultTurnMinutes: Int?
	public var active: Bool?

	public init(name: String? = nil, defaultTurnMinutes: Int? = nil, active: Bool? = nil) {
		self.name = name
		self.defaultTurnMinutes = defaultTurnMinutes
		self.active = active
	}
}

/// Wire name matches client `CreateCafeTableRequest`.
public struct CreateCafeTableRequest: Content, Sendable {
	public var areaId: String
	public var name: String
	public var capacity: Int
	public var accessible: Bool
	public var highTop: Bool?
	public var outside: Bool?
	public var active: Bool

	public init(
		areaId: String,
		name: String,
		capacity: Int,
		accessible: Bool = false,
		highTop: Bool? = nil,
		outside: Bool? = nil,
		active: Bool = true
	) {
		self.areaId = areaId
		self.name = name
		self.capacity = capacity
		self.accessible = accessible
		self.highTop = highTop
		self.outside = outside
		self.active = active
	}
}

/// Wire name matches client update payloads when present.
public struct UpdateCafeTableRequest: Content, Sendable {
	public var areaId: String?
	public var name: String?
	public var capacity: Int?
	public var accessible: Bool?
	public var highTop: Bool?
	public var outside: Bool?
	public var active: Bool?

	public init(
		areaId: String? = nil,
		name: String? = nil,
		capacity: Int? = nil,
		accessible: Bool? = nil,
		highTop: Bool? = nil,
		outside: Bool? = nil,
		active: Bool? = nil
	) {
		self.areaId = areaId
		self.name = name
		self.capacity = capacity
		self.accessible = accessible
		self.highTop = highTop
		self.outside = outside
		self.active = active
	}
}

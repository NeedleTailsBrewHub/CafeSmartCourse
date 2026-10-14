//
//  ArrayResponseWrappers.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on August 19, 2025
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmartAPI Project
//

import Vapor

public struct OrdersWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var items: [Order]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}
public struct InventoryItemsWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var items: [InventoryItem]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}
struct UsersWrapper: Content, Sendable, BinaryResponseEncodable {
	public var items: [UserPublic]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}
public struct SeatingAreasWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var items: [SeatingArea]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}
public struct TablesWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var items: [CafeTable]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}


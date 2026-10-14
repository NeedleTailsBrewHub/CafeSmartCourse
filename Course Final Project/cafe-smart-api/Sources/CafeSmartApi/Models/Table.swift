//
//  Table.swift
//  CafeSmartApi
//
//  Created by Cole M on 9/2/25.
//
import Vapor

public struct Table: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var id: String
    public var areaId: String
    public var name: String
    public var capacity: Int
    public var accessible: Bool
    public var highTop: Bool?
    public var outside: Bool?
    public var active: Bool

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

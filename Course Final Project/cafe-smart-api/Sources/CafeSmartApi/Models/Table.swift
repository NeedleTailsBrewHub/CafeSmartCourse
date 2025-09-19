//
//  Table.swift
//  CafeSmartApi
//
//  Created by Cole M on 9/2/25.
//
import Vapor
import BSON

public struct Table: Content, Sendable, Equatable, AsyncResponseEncodable {
    public var id: String
    public var areaId: String
    public var name: String
    public var capacity: Int
    public var accessible: Bool
    public var highTop: Bool?
    public var outside: Bool?
    public var active: Bool
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

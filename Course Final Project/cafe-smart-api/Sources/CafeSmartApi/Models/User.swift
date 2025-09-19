//
//  User.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//

import Foundation
import Vapor
import BSON

public struct User: Content, Sendable, Equatable {
    public var id: String
    public var email: String
    public var name: String?
    public var isAdmin: Bool
    public var passwordHash: String
    public var symmetricKey: Data
    public var createdAt: Date
}


struct UsersWrapper: Content, Sendable, AsyncResponseEncodable {
    public var items: [UserPublic]
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

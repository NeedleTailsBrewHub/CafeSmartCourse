//
//  User.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//

import Foundation
import Vapor

public struct User: Content, Sendable, Equatable {
    public var id: String
    public var email: String
    public var name: String?
    public var isAdmin: Bool
    public var passwordHash: String
    public var symmetricKey: Data
    public var createdAt: Date
}


struct UsersWrapper: Content, Sendable, BinaryResponseEncodable {
    public var items: [UserPublic]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

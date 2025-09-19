//
//  Token.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//

import Foundation

public struct RefreshToken: Codable, Sendable, Equatable {
    public var _id: String // user id
    public var token: String
    public var expiresAt: Date
    public var issuedAt: Date
}

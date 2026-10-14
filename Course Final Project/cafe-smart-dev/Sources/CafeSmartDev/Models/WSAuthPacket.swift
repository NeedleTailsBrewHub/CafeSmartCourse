//
//  WSAuthPacket.swift
//  CafeSmartDev
//
//  First binary frame after WS connect — must match API `WSAuthPacket`.
//

import Foundation

public struct WSAuthPacket: Codable, Sendable, Equatable {
    public var token: String
    public var topic: String

    public init(token: String, topic: String) {
        self.token = token
        self.topic = topic
    }
}

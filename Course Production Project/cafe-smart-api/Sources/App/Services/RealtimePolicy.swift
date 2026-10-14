//
//  RealtimePolicy.swift
//  CafeSmartAPI
//
//  Server-authoritative realtime: clients authenticate and receive publishes;
//  they do not relay arbitrary peer frames.
//

enum RealtimePolicy {
    /// When false, authenticated inbound binary/text frames are ignored (ping/pong still work).
    static let relayAuthenticatedPeerFrames = false
}

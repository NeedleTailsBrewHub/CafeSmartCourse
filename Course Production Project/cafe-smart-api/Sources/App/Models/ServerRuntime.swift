//
//  ServerRuntime.swift
//  CafeSmartAPI
//
//  Server-driven flags for client UI (demo affordances, etc.).
//

import Vapor

public struct ServerRuntime: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var demoMode: Bool

    public init(demoMode: Bool) {
        self.demoMode = demoMode
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// DEBUG + `SEED_TEST_DATA=true` enables demo seeding and client demo UI.
/// Release builds always report disabled.
enum DemoModePolicy {
    static var isEnabled: Bool {
        #if DEBUG
        (Environment.get("SEED_TEST_DATA") ?? "").lowercased() == "true"
        #else
        false
        #endif
    }
}

//
//  DemoModeRuntimeTests.swift
//  ApiTests
//

import Testing
import Vapor
@testable import cafe_smart_api

@Suite("DemoModeRuntime")
struct DemoModeRuntimeTests {
    @Test func runtimeDemoModeFalseByDefault() async throws {
        try await APITestHelpers.withApp(adminEmail: "runtime-off@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "runtime-off@example.com")
            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/runtime", token: token)
            #expect(res.status == .ok)
            let runtime = try APITestHelpers.decodeBody(ServerRuntime.self, from: res)
            #expect(runtime.demoMode == false)
            #expect(DemoModePolicy.isEnabled == false)
        }
    }

    @Test func runtimeDemoModeTrueWhenSeedFlagSet() async throws {
        #if !DEBUG
        // Release API always reports demoMode false (compile-gated).
        #expect(DemoModePolicy.isEnabled == false)
        return
        #else
        try await APITestHelpers.withApp(adminEmail: "runtime-on@example.com") { app in
            let (_, token) = try await APITestHelpers.registerAndLogin(
                app: app, email: "runtime-on@example.com")
            setenv("SEED_TEST_DATA", "true", 1)
            defer { setenv("SEED_TEST_DATA", "false", 1) }
            #expect(DemoModePolicy.isEnabled == true)
            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/runtime", token: token)
            #expect(res.status == .ok)
            let runtime = try APITestHelpers.decodeBody(ServerRuntime.self, from: res)
            #expect(runtime.demoMode == true)
        }
        #endif
    }
}

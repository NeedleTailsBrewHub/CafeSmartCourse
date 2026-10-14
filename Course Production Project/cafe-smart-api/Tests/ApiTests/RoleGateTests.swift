//
//  RoleGateTests.swift
//  ApiTests
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct RoleGateTests {

    @Test func adminReceivesStaffRolesGuestDoesNot() async throws {
        let adminEmail = "role-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (guest, _) = try await APITestHelpers.registerAndLogin(
                app: app, email: "role-guest@example.com")
            let (admin, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            let guestUser = User(
                id: guest.id,
                email: guest.email,
                name: guest.name,
                isAdmin: false,
                passwordHash: "x",
                symmetricKey: Data(repeating: 1, count: 32),
                createdAt: Date())
            #expect(RoleGate.roles(for: guestUser) == [.guest])

            let adminUser = User(
                id: admin.id,
                email: admin.email,
                name: admin.name,
                isAdmin: true,
                passwordHash: "x",
                symmetricKey: Data(repeating: 1, count: 32),
                createdAt: Date())
            let adminRoles = RoleGate.roles(for: adminUser)
            #expect(adminRoles.contains(.manager))
            #expect(adminRoles.contains(.owner))

            // Sample admin route still works for admin + request id header.
            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory?limit=1", token: adminToken)
            #expect(res.status == .ok)
            #expect(res.headers.first(name: "X-Request-ID") != nil)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func teamListEmptyWithoutSeedFlag() async throws {
        let adminEmail = "team-empty-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let res = try await APITestHelpers.request(
                app, .GET, "/api/auth/team", token: adminToken)
            #expect(res.status == .ok)
            let body = try APITestHelpers.decodeBody(TeamMembersWrapper.self, from: res)
            #expect(body.items.isEmpty)
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

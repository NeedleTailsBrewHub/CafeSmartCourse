//
//  VenueRoleTests.swift
//  ApiTests
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct VenueRoleTests {

    @Test func roleGateMapsPersistedRoles() {
        let staff = User(
            id: "1", email: "s@test.com", isAdmin: false, venueRole: .staff,
            passwordHash: "x", symmetricKey: Data(repeating: 1, count: 32), createdAt: Date())
        #expect(RoleGate.venueRole(for: staff) == .staff)
        #expect(RoleGate.isMerchantFloor(for: staff))
        #expect(RoleGate.roles(for: staff).contains(.barista))

        let manager = User(
            id: "2", email: "m@test.com", isAdmin: false, venueRole: .manager,
            passwordHash: "x", symmetricKey: Data(repeating: 1, count: 32), createdAt: Date())
        #expect(RoleGate.venueRole(for: manager) == .manager)
        #expect(RoleGate.roles(for: manager).contains(.manager))

        let guest = User(
            id: "3", email: "g@test.com", isAdmin: false, venueRole: .guest,
            passwordHash: "x", symmetricKey: Data(repeating: 1, count: 32), createdAt: Date())
        #expect(RoleGate.roles(for: guest) == [.guest])
    }

    @Test func staffForbiddenOnInventoryAndReportsAllowedOnRecipesRead() async throws {
        let adminEmail = "venue-role-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let (staffUser, staffToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "venue-staff@example.com")

            let assignRes = try await APITestHelpers.request(
                app, .PUT, "/api/auth/users/\(staffUser.id)/role",
                token: adminToken,
                body: AssignVenueRoleRequest(venueRole: .staff, teamMemberId: nil))
            #expect(assignRes.status == .ok)

            let inv = try await APITestHelpers.request(
                app, .GET, "/api/auth/inventory?limit=1", token: staffToken)
            #expect(inv.status.code == 995)

            let reports = try await APITestHelpers.request(
                app, .GET, "/api/auth/reports/summary", token: staffToken)
            #expect(reports.status.code == 995)

            let recipes = try await APITestHelpers.request(
                app, .GET, "/api/auth/recipes", token: staffToken)
            #expect(recipes.status == .ok)

            let seating = try await APITestHelpers.request(
                app, .GET, "/api/auth/seating/areas", token: staffToken)
            #expect(seating.status == .ok)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func staffClockPrivacyAndSelfOnly() async throws {
        let adminEmail = "clock-privacy-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            let a = try await createMember(app: app, token: adminToken, name: "Alpha")
            let b = try await createMember(app: app, token: adminToken, name: "Beta")

            let (staffUser, staffToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "clock-staff@example.com")
            let assignRes = try await APITestHelpers.request(
                app, .PUT, "/api/auth/users/\(staffUser.id)/role",
                token: adminToken,
                body: AssignVenueRoleRequest(venueRole: .staff, teamMemberId: a.id))
            #expect(assignRes.status == .ok)

            let list = try await APITestHelpers.request(
                app, .GET, "/api/auth/team", token: staffToken)
            #expect(list.status == .ok)
            let members = try APITestHelpers.decodeBody(TeamMembersWrapper.self, from: list)
            #expect(members.items.count == 1)
            #expect(members.items.first?.id == a.id)
            #expect(members.items.first?.hourlyRateCents == nil)

            let peerClock = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(b.id)/clock-in", token: staffToken)
            #expect([403, 995].contains(Int(peerClock.status.code)))

            let selfClock = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(a.id)/clock-in", token: staffToken)
            #expect(selfClock.status == .ok)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func cannotDemoteLastAdmin() async throws {
        let adminEmail = "last-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (admin, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let res = try await APITestHelpers.request(
                app, .PUT, "/api/auth/users/\(admin.id)/role",
                token: adminToken,
                body: AssignVenueRoleRequest(venueRole: .staff, teamMemberId: nil))
            #expect(res.status == .forbidden || res.status == .conflict)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func autoTrainTickFiresOncePerMonth() async throws {
        let adminEmail = "auto-train-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail) { app in
            app.processRunner = FakeProcessRunner(exitCode: 0, writeEmptyOutFile: true)
        }
        do {
            setenv("AUTO_TRAIN_ENABLED", "true", 1)
            setenv("AUTO_TRAIN_DAY", "1", 1)
            setenv("AUTO_TRAIN_HOUR_UTC", "0", 1)
            TrainScheduleService.resetForTests(app: app)

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var comps = DateComponents()
            comps.year = 2026
            comps.month = 8
            comps.day = 1
            comps.hour = 10
            let now = calendar.date(from: comps)!

            let first = await TrainScheduleService.tick(app: app, now: now)
            #expect(first == true)
            let second = await TrainScheduleService.tick(app: app, now: now)
            #expect(second == false)

            let status = await TrainScheduleService.status(app: app)
            #expect(status.lastRunYearMonth == "2026-08")

            unsetenv("AUTO_TRAIN_ENABLED")
            unsetenv("AUTO_TRAIN_DAY")
            unsetenv("AUTO_TRAIN_HOUR_UTC")
        }
        try await APITestHelpers.shutdownApp(app)
    }

    private func createMember(app: Application, token: String, name: String) async throws -> TeamMember {
        let res = try await APITestHelpers.request(
            app, .POST, "/api/auth/team",
            token: token,
            body: CreateTeamMemberRequest(
                name: name, role: "Barista", shift: "Morning", hourlyRateCents: 1800))
        #expect(res.status == .ok)
        return try APITestHelpers.decodeBody(TeamMember.self, from: res)
    }
}

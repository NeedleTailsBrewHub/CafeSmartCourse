//
//  TeamClockTests.swift
//  ApiTests
//
//  Clock on / off + open-punch visibility in timesheet summary.
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct TeamClockTests {

    @Test func clockInThenOutHappyPath() async throws {
        let adminEmail = "clock-happy@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, token) = try await APITestHelpers.registerAndLogin(app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team",
                token: token,
                body: CreateTeamMemberRequest(
                    name: "Clock Tester", role: "Barista", shift: "Morning", hourlyRateCents: 1800))
            #expect(createRes.status == .ok || createRes.status == .created)
            let member = try APITestHelpers.decodeBody(TeamMember.self, from: createRes)

            let inRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(member.id)/clock-in", token: token)
            #expect(inRes.status == .ok)
            let open = try APITestHelpers.decodeBody(TimeEntry.self, from: inRes)
            #expect(open.teamMemberId == member.id)
            #expect(open.clockOut == nil)
            #expect(open.source == .clock)

            let again = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(member.id)/clock-in", token: token)
            #expect(again.status == .conflict)

            let outRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(member.id)/clock-out", token: token)
            #expect(outRes.status == .ok)
            let closed = try APITestHelpers.decodeBody(TimeEntry.self, from: outRes)
            #expect(closed.id == open.id)
            #expect(closed.clockOut != nil)

            let outAgain = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(member.id)/clock-out", token: token)
            #expect(outAgain.status == .conflict)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func openPunchAppearsInPastWeekSummary() async throws {
        let adminEmail = "clock-summary@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, token) = try await APITestHelpers.registerAndLogin(app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team",
                token: token,
                body: CreateTeamMemberRequest(
                    name: "Open Punch", role: "Barista", shift: "Mid"))
            let member = try APITestHelpers.decodeBody(TeamMember.self, from: createRes)

            let inRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(member.id)/clock-in", token: token)
            #expect(inRes.status == .ok)
            let open = try APITestHelpers.decodeBody(TimeEntry.self, from: inRes)

            let pastAnchor = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date()) ?? Date()
            let iso = ISO8601DateFormatter().string(from: pastAnchor)
            let enc = iso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? iso
            let summaryRes = try await APITestHelpers.request(
                app, .GET,
                "/api/auth/team/time-summary?period=week&anchor=\(enc)",
                token: token)
            #expect(summaryRes.status == .ok)
            let summary = try APITestHelpers.decodeBody(TimePeriodSummary.self, from: summaryRes)
            #expect(summary.entries.contains(where: { $0.id == open.id && $0.clockOut == nil }))
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func deleteMemberRemovesOpenPunches() async throws {
        let adminEmail = "clock-delete@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (_, token) = try await APITestHelpers.registerAndLogin(app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/team",
                token: token,
                body: CreateTeamMemberRequest(
                    name: "Temp Hire", role: "Host", shift: "Evening"))
            let member = try APITestHelpers.decodeBody(TeamMember.self, from: createRes)
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/team/\(member.id)/clock-in", token: token)

            let del = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/team/\(member.id)", token: token)
            #expect(del.status == .noContent || del.status == .ok)

            let entries = try await APITestHelpers.request(
                app, .GET, "/api/auth/team/time-entries?limit=100", token: token)
            #expect(entries.status == .ok)
            let listed = try APITestHelpers.decodeBody(TimeEntriesWrapper.self, from: entries)
            #expect(!listed.items.contains(where: { $0.teamMemberId == member.id }))
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

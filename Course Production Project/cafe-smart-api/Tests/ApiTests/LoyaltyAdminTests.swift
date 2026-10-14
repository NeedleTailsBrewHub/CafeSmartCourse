//
//  LoyaltyAdminTests.swift
//  ApiTests
//
//  Accrue/redeem are admin-only; get/enroll remain self-or-admin.
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct LoyaltyAdminTests {

    @Test func guestAccrueIsForbidden() async throws {
        let adminEmail = "loyalty-acl-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (user, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "loyalty-acl-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            struct Enroll: Content { let userId: String }
            var res = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/enroll",
                token: userToken, body: Enroll(userId: user.id))
            #expect(res.status == .ok || res.status == .created)

            struct Accrue: Content { let userId: String; let points: Int }
            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/accrue",
                token: userToken, body: Accrue(userId: user.id, points: 50))
            #expect(
                res.status == .forbidden
                    || res.status == .unauthorized
                    || res.status.code == 995)

            res = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/accrue",
                token: adminToken, body: Accrue(userId: user.id, points: 50))
            #expect(res.status == .ok)
            let account = try APITestHelpers.decodeBody(LoyaltyAccountPublic.self, from: res)
            #expect(account.points >= 50)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func guestRedeemIsForbidden() async throws {
        let adminEmail = "loyalty-redeem-admin@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail)
        do {
            let (user, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "loyalty-redeem-guest@example.com")
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)

            struct Enroll: Content { let userId: String }
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/enroll",
                token: adminToken, body: Enroll(userId: user.id))

            struct Accrue: Content { let userId: String; let points: Int }
            _ = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/accrue",
                token: adminToken, body: Accrue(userId: user.id, points: 100))

            struct Redeem: Content { let userId: String; let points: Int }
            let res = try await APITestHelpers.request(
                app, .POST, "/api/auth/loyalty/redeem",
                token: userToken, body: Redeem(userId: user.id, points: 10))
            #expect(
                res.status == .forbidden
                    || res.status == .unauthorized
                    || res.status.code == 995)
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

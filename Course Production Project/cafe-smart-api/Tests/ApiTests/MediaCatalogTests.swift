//
//  MediaCatalogTests.swift
//  ApiTests
//

import Foundation
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct MediaCatalogTests {

    // Minimal 1×1 PNG
    static let png1x1: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
        0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90,
        0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8,
        0xCF, 0xC0, 0x00, 0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE, 0xD4, 0xEF, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]

    // MARK: - Phase 0 contracts

    @Test func validatorAcceptsPNG() throws {
        let result = try MediaImageValidator.validate(
            bytes: Self.png1x1, declaredContentType: "image/png")
        #expect(result.contentType == "image/png")
        #expect(result.ext == "png")
    }

    @Test func validatorRejectsEmptyAndMagicMismatch() {
        #expect(throws: MediaError.emptyBody) {
            try MediaImageValidator.validate(bytes: [], declaredContentType: "image/png")
        }
        #expect(throws: MediaError.magicMismatch) {
            try MediaImageValidator.validate(
                bytes: Self.png1x1, declaredContentType: "image/jpeg")
        }
    }

    @Test func validatorRejectsOversize() {
        #expect(throws: MediaError.payloadTooLarge(max: 10)) {
            try MediaImageValidator.validate(
                bytes: Self.png1x1, declaredContentType: "image/png", maxBytes: 10)
        }
    }

    @Test func mediaKeyRejectsTraversal() {
        #expect(throws: MediaError.invalidMenuItemId) {
            try MediaKey.make(menuItemId: "../evil", ext: "png")
        }
        let key = try! MediaKey.make(menuItemId: "abc123", ext: "png")
        #expect(key.hasPrefix("menu/abc123/"))
        #expect(key.hasSuffix(".png"))
    }

    @Test func fakeMediaStoragePutDelete() async throws {
        let fake = FakeMediaStorage(publicBaseURL: "https://media.test")
        let put = try await fake.put(key: "menu/a/b.png", contentType: "image/png", bytes: [1, 2])
        #expect(put.publicURL == "https://media.test/menu/a/b.png")
        try await fake.delete(key: "menu/a/b.png")
        let deletes = await fake.deletes
        #expect(deletes == ["menu/a/b.png"])
    }

    @Test func catalogVersionBumpMonotonic() async throws {
        let app = try await APITestHelpers.makeApp(adminEmail: "catalog-ver@example.com")
        do {
            let v0 = try await app.catalogVersions.current()
            #expect(v0.version == 0)
            let v1 = try await app.catalogVersions.bump(reason: "test")
            let v2 = try await app.catalogVersions.bump(reason: "test2")
            #expect(v1.version == 1)
            #expect(v2.version == 2)
            #expect(v2.version > v1.version)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func manualImageURLPolicy() throws {
        #expect(try MediaURLPolicy.validateManualImageURL("/menu-images/x.png", allowedHosts: []) == "/menu-images/x.png")
        #expect(try MediaURLPolicy.validateManualImageURL("", allowedHosts: []) == "")
        #expect(throws: MediaURLPolicy.AbortReason.badImageURL) {
            try MediaURLPolicy.validateManualImageURL("http://evil.com/a.png", allowedHosts: ["media.test"])
        }
        #expect(
            try MediaURLPolicy.validateManualImageURL(
                "https://media.test/a.png", allowedHosts: ["media.test"]) == "https://media.test/a.png")
    }

    // MARK: - SigV4 / R2

    @Test func sigV4StableAuthorization() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)  // 2024-01-01T00:00:00Z
        let (amz, stamp) = S3SigV4.amzDate(from: date)
        #expect(amz == "20240101T000000Z")
        #expect(stamp == "20240101")
        let canonical = S3SigV4.canonicalRequest(
            method: "PUT",
            canonicalURI: "/bucket/menu/a.png",
            canonicalQueryString: "",
            canonicalHeaders: "host:example.com\nx-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nx-amz-date:\(amz)\n",
            signedHeaders: "host;x-amz-content-sha256;x-amz-date",
            payloadHash: S3SigV4.hexSHA256([]))
        let auth = S3SigV4.authorizationHeader(
            credentials: .init(accessKeyId: "AKIA", secretAccessKey: "secret"),
            region: "auto",
            service: "s3",
            amzDate: amz,
            dateStamp: stamp,
            canonicalRequest: canonical,
            signedHeaders: "host;x-amz-content-sha256;x-amz-date")
        #expect(auth.contains("AWS4-HMAC-SHA256 Credential=AKIA/\(stamp)/auto/s3/aws4_request"))
        #expect(auth.contains("Signature="))
    }

    actor RecordingHTTP: HTTPClientPerforming {
        var last: MediaHTTPRequest?
        func execute(_ request: MediaHTTPRequest) async throws -> MediaHTTPResponse {
            last = request
            return MediaHTTPResponse(status: 200)
        }
    }

    @Test func r2PutSignsRequest() async throws {
        let http = RecordingHTTP()
        let storage = R2MediaStorage(
            config: R2MediaConfig(
                accountId: "acc",
                accessKeyId: "key",
                secretAccessKey: "secret",
                bucket: "bucket",
                publicBaseURL: "https://media.example.com",
                cacheMaxAgeSeconds: 3600),
            http: http,
            now: { Date(timeIntervalSince1970: 1_704_067_200) })
        let result = try await storage.put(
            key: "menu/x/y.png", contentType: "image/png", bytes: Self.png1x1)
        #expect(result.publicURL == "https://media.example.com/menu/x/y.png")
        let req = await http.last
        #expect(req?.method == "PUT")
        #expect(req?.headers["Authorization"] != nil)
        #expect(req?.headers["Cache-Control"] == "public, max-age=3600")
        #expect(req?.headers["Content-Type"] == "image/png")
    }

    // MARK: - HTTP API

    @Test func uploadImageSetsURLAndBumpsVersion() async throws {
        let adminEmail = "media-upload@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail) { app in
            app.mediaStorage = FakeMediaStorage(publicBaseURL: "https://media.test")
        }
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Latte", priceCents: 400, isAvailable: true, category: "Coffee"))
            let item = try APITestHelpers.decodeBody(MenuItem.self, from: createRes)
            let vAfterCreate = try await app.catalogVersions.current()

            var headers: HTTPHeaders = [:]
            headers.replaceOrAdd(name: .authorization, value: "Bearer \(adminToken)")
            headers.replaceOrAdd(name: .contentType, value: "application/octet-stream")
            let uploadRes = try await APITestHelpers.rawRequest(
                app,
                method: .POST,
                path: "/api/auth/menu/\(item.id)/image?contentType=image/png",
                headers: headers,
                body: Data(Self.png1x1))
            #expect(uploadRes.status == .ok)
            let updated = try APITestHelpers.decodeBody(MenuItem.self, from: uploadRes)
            #expect(updated.imageURL?.hasPrefix("https://media.test/menu/") == true)
            #expect(updated.imageMediaKey != nil)
            let vAfterUpload = try await app.catalogVersions.current()
            #expect(vAfterUpload.version > vAfterCreate.version)

            let listRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/menu", token: adminToken)
            let page = try APITestHelpers.decodeBody(PaginatedMenuItems.self, from: listRes)
            #expect(page.catalogVersion == vAfterUpload.version)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func uploadRejectsBadMagic() async throws {
        let adminEmail = "media-bad@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail) { app in
            app.mediaStorage = FakeMediaStorage()
        }
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Tea", priceCents: 300, isAvailable: true))
            let item = try APITestHelpers.decodeBody(MenuItem.self, from: createRes)
            var headers: HTTPHeaders = [:]
            headers.replaceOrAdd(name: .authorization, value: "Bearer \(adminToken)")
            headers.replaceOrAdd(name: .contentType, value: "application/octet-stream")
            let fake = app.mediaStorage as! FakeMediaStorage
            let uploadRes = try await APITestHelpers.rawRequest(
                app,
                method: .POST,
                path: "/api/auth/menu/\(item.id)/image?contentType=image/jpeg",
                headers: headers,
                body: Data(Self.png1x1))
            #expect(uploadRes.status == .badRequest)
            let puts = await fake.puts
            #expect(puts.isEmpty)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func clearImageAndCatalogVersionEndpoint() async throws {
        let adminEmail = "media-clear@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail) { app in
            app.mediaStorage = FakeMediaStorage(publicBaseURL: "https://media.test")
        }
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Mocha", priceCents: 500, isAvailable: true))
            let item = try APITestHelpers.decodeBody(MenuItem.self, from: createRes)
            var headers: HTTPHeaders = [:]
            headers.replaceOrAdd(name: .authorization, value: "Bearer \(adminToken)")
            headers.replaceOrAdd(name: .contentType, value: "application/octet-stream")
            _ = try await APITestHelpers.rawRequest(
                app,
                method: .POST,
                path: "/api/auth/menu/\(item.id)/image?contentType=image/png",
                headers: headers,
                body: Data(Self.png1x1))
            let clearRes = try await APITestHelpers.request(
                app, .DELETE, "/api/auth/menu/\(item.id)/image", token: adminToken)
            #expect(clearRes.status == .ok)
            let cleared = try APITestHelpers.decodeBody(MenuItem.self, from: clearRes)
            #expect(cleared.imageURL == nil)
            #expect(cleared.imageMediaKey == nil)

            let verRes = try await APITestHelpers.request(
                app, .GET, "/api/auth/menu/catalog-version", token: adminToken)
            #expect(verRes.status == .ok)
            let ver = try APITestHelpers.decodeBody(CatalogVersion.self, from: verRes)
            #expect(ver.version >= 2)
        }
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func nonAdminCannotUpload() async throws {
        let adminEmail = "media-admin-gate@example.com"
        let app = try await APITestHelpers.makeApp(adminEmail: adminEmail) { app in
            app.mediaStorage = FakeMediaStorage()
        }
        do {
            let (_, adminToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: adminEmail)
            let (_, userToken) = try await APITestHelpers.registerAndLogin(
                app: app, email: "guest-media@example.com")
            let createRes = try await APITestHelpers.request(
                app, .POST, "/api/auth/menu",
                token: adminToken,
                body: CreateMenuItemRequest(
                    name: "Cookie", priceCents: 200, isAvailable: true))
            let item = try APITestHelpers.decodeBody(MenuItem.self, from: createRes)
            var headers: HTTPHeaders = [:]
            headers.replaceOrAdd(name: .authorization, value: "Bearer \(userToken)")
            headers.replaceOrAdd(name: .contentType, value: "application/octet-stream")
            let uploadRes = try await APITestHelpers.rawRequest(
                app,
                method: .POST,
                path: "/api/auth/menu/\(item.id)/image?contentType=image/png",
                headers: headers,
                body: Data(Self.png1x1))
            #expect(uploadRes.status != .ok)
        }
        try await APITestHelpers.shutdownApp(app)
    }
}

//
//  APITestHelpers.swift
//  ApiTests
//

import BinaryCodable
import Foundation
import NIO
import NIOHTTP1
import Testing
import Vapor
@testable import cafe_smart_api

/// Serializes ADMIN_USERNAMES setenv across parallel Swift Testing suites.
actor APITestEnvGate {
    static let shared = APITestEnvGate()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter(adminEmail: String) async {
        while busy {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
        }
        busy = true
        setenv("MLDSA_SEED", "0123456789abcdef0123456789abcdef", 1)
        setenv("USE_TEST_STORE", "true", 1)
        setenv("SEED_TEST_DATA", "false", 1)
        setenv("WS_AUTH_TIMEOUT_SECONDS", "2", 1)
        setenv("ADMIN_USERNAMES", adminEmail, 1)
        clearPaymentsEnv()
    }

    /// Payments off by default — prepaid suites opt in via `enableFakePaymentsEnv`.
    /// Call again after `Application.make` because dotenv can reload host `.env`.
    func clearPaymentsEnv() {
        unsetenv("PAYMENTS_ENABLED")
        unsetenv("STRIPE_SECRET_KEY")
        unsetenv("STRIPE_PUBLISHABLE_KEY")
        unsetenv("STRIPE_WEBHOOK_SECRET")
        unsetenv("STRIPE_TAX_ENABLED")
        unsetenv("STRIPE_TAX_CODE")
        unsetenv("STRIPE_TAX_ADDRESS_LINE1")
        unsetenv("STRIPE_TAX_ADDRESS_CITY")
        unsetenv("STRIPE_TAX_ADDRESS_STATE")
        unsetenv("STRIPE_TAX_ADDRESS_POSTAL_CODE")
        unsetenv("STRIPE_TAX_ADDRESS_COUNTRY")
    }

    func leave() {
        busy = false
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.resume()
    }
}

enum APITestHelpers {
    /// Enable FakeStripe for prepaid checkout tests (call from `beforeConfigure` after enter).
    static func enableFakePaymentsEnv() {
        setenv("PAYMENTS_ENABLED", "1", 1)
        setenv("STRIPE_SECRET_KEY", "sk_test_fake", 1)
        setenv("STRIPE_PUBLISHABLE_KEY", "pk_test_fake", 1)
        setenv("STRIPE_WEBHOOK_SECRET", "whsec_test_fake", 1)
        setenv("STRIPE_CURRENCY", "usd", 1)
        setenv("STRIPE_MERCHANT_COUNTRY", "US", 1)
        setenv("STRIPE_TAX_ENABLED", "1", 1)
        setenv("STRIPE_TAX_ADDRESS_LINE1", "123 Test St", 1)
        setenv("STRIPE_TAX_ADDRESS_CITY", "Seattle", 1)
        setenv("STRIPE_TAX_ADDRESS_STATE", "WA", 1)
        setenv("STRIPE_TAX_ADDRESS_POSTAL_CODE", "98101", 1)
        setenv("STRIPE_TAX_ADDRESS_COUNTRY", "US", 1)
    }

    static func requestRaw(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = .init(),
        body: Data
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            collectedBody: .init(data: body),
            on: app.eventLoopGroup.next()
        )
        for header in headers {
            req.headers.replaceOrAdd(name: header.name, value: header.value)
        }
        return try await app.responder.respond(to: req).get()
    }

    /// Creates a testing Application under the global env gate.
    /// - Parameter beforeConfigure: Optional hook (e.g. inject FakeProcessRunner) before `configure`.
    static func makeApp(
        adminEmail: String,
        beforeConfigure: (@Sendable (Application) async throws -> Void)? = nil
    ) async throws -> Application {
        await APITestEnvGate.shared.enter(adminEmail: adminEmail)
        do {
            let app = try await Application.make(.testing)
            // Application.make may load repo `.env` and re-enable live Stripe keys.
            await APITestEnvGate.shared.clearPaymentsEnv()
            if let beforeConfigure {
                try await beforeConfigure(app)
            }
            try await configure(app)
            await AuthRateLimiter.shared.reset()
            return app
        } catch {
            await APITestEnvGate.shared.leave()
            throw error
        }
    }

    static func shutdownApp(_ app: Application) async throws {
        await app.realtime.stop()
        try await app.asyncShutdown()
        try await Task.sleep(for: .milliseconds(200))
        await APITestEnvGate.shared.leave()
    }

    /// Runs work with a testing app and always releases the env gate.
    static func withApp<T>(
        adminEmail: String,
        _ body: (Application) async throws -> T
    ) async throws -> T {
        let app = try await makeApp(adminEmail: adminEmail)
        var released = false
        do {
            let value = try await body(app)
            released = true
            try await shutdownApp(app)
            return value
        } catch {
            if !released {
                try? await shutdownApp(app)
            }
            throw error
        }
    }

    /// Raw body request (e.g. image octet-stream upload).
    static func rawRequest(
        _ app: Application,
        method: HTTPMethod,
        path: String,
        headers: HTTPHeaders = [:],
        body: Data
    ) async throws -> Response {
        var buffer = ByteBufferAllocator().buffer(capacity: body.count)
        buffer.writeBytes(body)
        let req = Request(
            application: app,
            method: method,
            url: URI(string: path),
            headers: headers,
            collectedBody: buffer,
            on: app.eventLoopGroup.next()
        )
        req.headers.replaceOrAdd(
            name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }

    static func request(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        if let token {
            req.headers.bearerAuthorization = .init(token: token)
        }
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }

    static func request<T: Content>(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        body: T
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        try req.content.encode(body, as: .json)
        if let token {
            req.headers.bearerAuthorization = .init(token: token)
        }
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/x-binary-codable")
        return try await app.responder.respond(to: req).get()
    }

    static func registerAndLogin(
        app: Application,
        email: String,
        password: String = "password123",
        name: String? = nil,
        requestAdmin: Bool = false
    ) async throws -> (user: UserPublic, token: String) {
        struct RegisterRequest: Content {
            let email: String
            let password: String
            let name: String?
            let isAdmin: Bool
        }
        _ = try await request(
            app, .POST, "/api/register",
            body: RegisterRequest(email: email, password: password, name: name, isAdmin: requestAdmin))

        struct LoginRequest: Content { let email: String; let password: String }
        struct TokenResponse: Content {
            let token: String
            let refreshToken: String?
            let expiresAt: Date
            let user: UserPublic
        }
        let res = try await request(
            app, .POST, "/api/login",
            body: LoginRequest(email: email, password: password))
        #expect(res.status == .ok)
        let body = try decodeBody(TokenResponse.self, from: res)
        return (body.user, body.token)
    }

    static func responseData(_ response: Response) -> Data {
        var buffer = response.body.buffer ?? ByteBuffer()
        return Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
    }

    static func decodeBody<T: Decodable>(_ type: T.Type, from response: Response) throws -> T {
        try BinaryDecoder().decode(type, from: responseData(response))
    }

    static func placeOrder(
        app: Application,
        token: String,
        customerName: String,
        notes: String? = nil,
        adminToken: String
    ) async throws -> Order {
        let menuRes = try await request(
            app, .POST, "/api/auth/menu",
            token: adminToken,
            body: CreateMenuItemRequest(
                name: "Latte",
                priceCents: 450,
                isAvailable: true))
        #expect(menuRes.status == .ok || menuRes.status == .created)
        let menu = try decodeBody(MenuItem.self, from: menuRes)
        let body = CreateOrderRequest(
            customerName: customerName,
            items: [OrderItem(menuItemId: menu.id, name: menu.name, quantity: 1, notes: notes)],
            pickupTime: nil,
            channel: .pickup,
            serviceType: .barista)
        let res = try await request(app, .POST, "/api/auth/orders", token: token, body: body)
        #expect(res.status == .ok || res.status == .created)
        return try decodeBody(Order.self, from: res)
    }
}

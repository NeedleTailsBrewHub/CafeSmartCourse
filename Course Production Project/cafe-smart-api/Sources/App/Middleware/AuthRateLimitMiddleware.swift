//
//  AuthRateLimitMiddleware.swift
//  CafeSmartAPI
//
//  Sliding-window rate limit for public auth endpoints (register / login / refresh).
//

import Foundation
import Vapor

actor AuthRateLimiter {
    static let shared = AuthRateLimiter()

    private var hits: [String: [Date]] = [:]
    /// Max attempts per key within `window`.
    var limit: Int = 20
    var window: TimeInterval = 60

    func reset() {
        hits.removeAll()
    }

    func allow(key: String, now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        var times = (hits[key] ?? []).filter { $0 >= cutoff }
        if times.count >= limit {
            hits[key] = times
            return false
        }
        times.append(now)
        hits[key] = times
        return true
    }
}

struct AuthRateLimitMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let ip = request.peerAddress?.ipAddress ?? request.remoteAddress?.ipAddress ?? "unknown"
        let key = "\(ip):\(request.url.path.lowercased())"
        guard await AuthRateLimiter.shared.allow(key: key) else {
            throw Abort(.tooManyRequests, reason: "Too many attempts. Try again later.")
        }
        return try await next.respond(to: request)
    }
}

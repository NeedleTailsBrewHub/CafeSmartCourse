//
//  MediaUploadRateLimiter.swift
//  CafeSmartAPI
//

import Foundation

public actor MediaUploadRateLimiter {
    private let limit: Int
    private let window: TimeInterval
    private var hits: [String: [Date]] = [:]

    public init(limit: Int = 30, windowSeconds: TimeInterval = 15 * 60) {
        self.limit = limit
        self.window = windowSeconds
    }

    public func check(adminId: String, now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-window)
        var times = (hits[adminId] ?? []).filter { $0 >= cutoff }
        if times.count >= limit {
            hits[adminId] = times
            throw MediaError.rateLimited
        }
        times.append(now)
        hits[adminId] = times
    }
}

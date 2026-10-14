//
//  AdminEnv.swift
//  CafeSmartAPI
//
//  Reads ADMIN_USERNAMES at call time via getenv so tests that mutate
//  process env with setenv are not defeated by Vapor Environment caching.
//

import Foundation
import Vapor

enum AdminEnv {
    /// Lowercased emails allowed to bootstrap/act as admin via ADMIN_USERNAMES.
    static func usernames() -> Set<String> {
        let raw: String
        if let cString = getenv("ADMIN_USERNAMES") {
            raw = String(cString: cString)
        } else {
            raw = Environment.get("ADMIN_USERNAMES") ?? ""
        }
        return Set(
            raw.split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })
    }

    static func isListedAdmin(email: String) -> Bool {
        usernames().contains(email.lowercased())
    }

    /// Effective admin for an authenticated user (DB flag, venue role, or env bootstrap list).
    static func isAdmin(user: User, requestIsAdmin: Bool = false) -> Bool {
        user.isAdmin
            || user.venueRole == .admin
            || requestIsAdmin
            || isListedAdmin(email: user.email)
    }
}

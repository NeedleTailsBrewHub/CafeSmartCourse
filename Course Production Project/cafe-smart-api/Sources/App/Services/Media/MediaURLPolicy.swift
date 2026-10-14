//
//  MediaURLPolicy.swift
//  CafeSmartAPI
//

import Foundation

public enum MediaURLPolicy: Sendable {
    /// Validates manual imageURL overrides. Empty string means clear (allowed).
    /// Relative `/menu-images/…` paths are allowed for local media storage.
    public static func validateManualImageURL(
        _ raw: String?,
        allowedHosts: Set<String>
    ) throws -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("/menu-images/") {
            guard !trimmed.contains("..") else { throw AbortReason.badImageURL }
            return trimmed
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw AbortReason.badImageURL
        }
        guard scheme == "https" else { throw AbortReason.badImageURL }
        // When no hosts configured (local), accept any https URL.
        if allowedHosts.isEmpty { return trimmed }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            throw AbortReason.badImageURL
        }
        return trimmed
    }

    public static func allowedHostsFromEnv(
        publicBaseURL: String?,
        extra: String?
    ) -> Set<String> {
        var hosts = Set<String>()
        if let publicBaseURL, let host = URL(string: publicBaseURL)?.host?.lowercased() {
            hosts.insert(host)
        }
        if let extra {
            for part in extra.split(separator: ",") {
                let h = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !h.isEmpty { hosts.insert(h) }
            }
        }
        return hosts
    }

    public enum AbortReason: Error, Sendable {
        case badImageURL
    }
}

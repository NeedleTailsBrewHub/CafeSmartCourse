//
//  StripeWebhookVerifier.swift
//  CafeSmartAPI
//
//  HMAC-SHA256 Stripe-Signature verification (t=…,v1=…).
//

import Crypto
import Foundation

enum StripeWebhookVerifier {
    /// Tolerance window for timestamp skew (seconds).
    static let tolerance: TimeInterval = 300

    static func verify(payload: Data, header: String, secret: String, now: Date = Date()) -> Bool {
        var timestamp: String?
        var signatures: [String] = []
        for part in header.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if kv[0] == "t" { timestamp = kv[1] }
            if kv[0] == "v1" { signatures.append(kv[1]) }
        }
        guard let timestamp, let ts = TimeInterval(timestamp), !signatures.isEmpty else {
            return false
        }
        if abs(now.timeIntervalSince1970 - ts) > tolerance { return false }
        let signed = "\(timestamp).".data(using: .utf8)! + payload
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        return signatures.contains(where: { constantTimeEqual($0, hex) })
    }

    /// Test helper: build a valid Stripe-Signature header for a payload.
    static func sign(payload: Data, secret: String, timestamp: TimeInterval? = nil) -> String {
        let t = Int(timestamp ?? Date().timeIntervalSince1970)
        let signed = "\(t).".data(using: .utf8)! + payload
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: signed, using: key)
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        return "t=\(t),v1=\(hex)"
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ad = Array(a.utf8)
        let bd = Array(b.utf8)
        guard ad.count == bd.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ad.count { diff |= ad[i] ^ bd[i] }
        return diff == 0
    }
}

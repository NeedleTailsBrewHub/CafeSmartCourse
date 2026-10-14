//
//  Constants.swift
//  cafe-smart-app
//
//  Created by Cole M on 12/22/25.
//

#if SKIP
import SkipFoundation
#else
import Foundation
#endif

@MainActor
enum Constants {
    /// Override with env `CAFE_API_HOST` or Info.plist key `CAFE_API_HOST` (devices / Release).
    static var wsHost: String { resolvedHost }

    static var httpHost: String {
#if DEBUG
        "http://\(wsHost):8080/"
#else
        "https://\(wsHost):8080/"
#endif
    }

    static let wsPort: Int = 8081

    static var wsEnableTLS: Bool {
#if DEBUG
        false
#else
        true
#endif
    }

    static let wsMerchantRoute: String = "/api/auth/ws/merchant"

    private static var resolvedHost: String {
        if let env = ProcessInfo.processInfo.environment["CAFE_API_HOST"], !env.isEmpty {
            return env
        }
#if !SKIP
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CAFE_API_HOST") as? String, !plist.isEmpty {
            return plist
        }
#endif
#if DEBUG
#if os(Android)
        return "10.0.2.2"
#else
        return "127.0.0.1"
#endif
#else
        print("CafeSmartDev: CAFE_API_HOST is not set; set env or Info.plist CAFE_API_HOST for Release builds.")
        return "api.invalid.local"
#endif
    }
}

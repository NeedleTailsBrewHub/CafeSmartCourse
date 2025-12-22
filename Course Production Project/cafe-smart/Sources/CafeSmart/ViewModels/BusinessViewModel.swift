//
//  BusinessViewModel.swift
//  CafeSmart
//
//  Created by NeedleTails on 8/19/25
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmart Project
//

import Observation
import SkipFuseUI
import BSON
import SkipKeychain
import JWTKit
#if SKIP
import SkipFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
@Observable
final class BusinessViewModel {
    // MARK: - State
    var config: BusinessConfig?
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - API
    func fetchConfig() async throws {
        isLoading = true
        defer { isLoading = false }
        let response: Response<BusinessConfig> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/config",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let conf = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        config = conf
    }

    func updateConfig(_ configUpdate: BusinessConfig) async throws -> BusinessConfig {
        // We send the whole config as an update; server will upsert or update as needed
        let body = try BSONEncoder().encode(configUpdate).makeData()
        let response: Response<BusinessConfig> = try await URLSession.shared.request(
            method: .put,
            httpHost: Constants.httpHost,
            url: "api/auth/config",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let conf = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        config = conf
        return conf
    }
}

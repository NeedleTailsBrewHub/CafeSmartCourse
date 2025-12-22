//
//  AuthenticationViewModel.swift
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
import ConnectionManagerKit
#if SKIP
import SkipFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@MainActor
enum Constants {
#if DEBUG
    static let httpHost: String = "http://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#else
    static let httpHost: String = "https://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#endif
}

@MainActor
@Observable
final class AuthenticationViewModel {
    
    let keychain = Keychain.shared
    
    var user: User?
    var didSignIn: Bool = false
    
    enum Errors: Error {
        case invalidData, failedRequest(Int)
    }
    
    func register(email: String, password: String) async throws {
        let registrationInfo = RegisterInfo(
            email: email,
            password: password,
            name: email,
            isAdmin: true)
        let body = try BSONEncoder().encode(registrationInfo).makeData()
        let response: Response<User> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/register",
            token: nil,
            body: body)
        let httpResponse = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Errors.failedRequest(httpResponse.statusCode)
        }
    }
    
    func login(email: String, password: String) async throws {
        let loginInfo = LoginInfo(
            email: email,
            password: password)
        let body = try BSONEncoder().encode(loginInfo).makeData()
        let response: Response<TokenResponse> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/login",
            token: nil,
            body: body)
        
        let httpResponse = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Errors.failedRequest(httpResponse.statusCode)
        }
        guard let token = response.data else {
            throw Errors.invalidData
        }
        self.user = token.user
        try keychain.set(token.token, forKey: "access-token")
        if let refreshToken = token.refreshToken {
            try keychain.set(refreshToken, forKey: "refresh-token")
        }
        self.didSignIn = true
        try await WebSocketClient.shared.connect(
            host: Constants.wsHost,
            route: "/api/auth/ws/merchant",
            headers: .init([("Authorization", "Bearer \(token.token)")]))
        try await Task.sleep(until: .now + .seconds(2))
        try await WebSocketClient.shared.sendPing("ping_data".data(using: .utf8)!, to: "/api/auth/ws/merchant")
    }
    
    func updatePassword(
        email: String,
        oldPassword: String,
        newPassword: String
    ) async throws {
        let payload = UpdatePasswordInfo(oldPassword: oldPassword, newPassword: newPassword)
        let body = try BSONEncoder().encode(payload).makeData()
        let response: Response<TokenResponse> = try await URLSession.shared.request(
            method: .put,
            httpHost: Constants.httpHost,
            url: "api/auth/update-password",
            token: nil,
            body: body)
        
        let httpResponse = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Errors.failedRequest(httpResponse.statusCode)
        }
        guard let token = response.data else {
            throw Errors.invalidData
        }
        self.user = token.user
        try keychain.set(token.token, forKey: "access-token")
        if let refreshToken = token.refreshToken {
            try keychain.set(refreshToken, forKey: "refresh-token")
        }
        self.didSignIn = true
    }
    
    
    func refreshToken() async throws {
        
        guard let refreshToken = try? keychain.string(forKey: "refresh-token") else {
            throw Errors.invalidData
        }
        let response: Response<Data> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/auth/refresh",
            headers: ["Authorization": "Bearer \(refreshToken)"],
            token: nil)
        
        let httpResponse = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Errors.failedRequest(httpResponse.statusCode)
        }
        
        guard let data = response.data else {
            throw Errors.invalidData
        }
        let decoded = try BSONDecoder().decode(TokenResponse.self, from: Document(data: data))
        self.user = decoded.user
        try keychain.set(decoded.token, forKey: "access-token")
        if let refreshToken = decoded.refreshToken {
            try keychain.set(refreshToken, forKey: "refresh-token")
        }
    }

    // MARK: - Session management
    func logout() async throws {
        let response: Response<Data> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/auth/logout",
            token: nil,
            body: Data()
        )
        let httpResponse = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Errors.failedRequest(httpResponse.statusCode)
        }
        signOut()
    }
    
    func signOut() {
        try? keychain.removeValue(forKey: "access-token")
        try? keychain.removeValue(forKey: "refresh-token")
        user = nil
        didSignIn = false
    }

    func deleteAccount() async throws {
        let response: Response<Data> = try await URLSession.shared.request(
            method: .delete,
            httpHost: Constants.httpHost,
            url: "api/auth/account",
            token: nil,
            body: Data()
        )
        let httpResponse = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Errors.failedRequest(httpResponse.statusCode)
        }
        signOut()
    }
    
    func deleteAccountLocally() {
        // Placeholder: call backend when endpoint is available
        signOut()
    }
}

// moved to Models/AuthModels.swift

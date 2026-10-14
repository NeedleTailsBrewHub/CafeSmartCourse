//
//  AuthenticationViewModel.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/8/25.
//
import Foundation
import Observation
import SkipFuse
import SkipKeychain
import BinaryCodable
import ConnectionManagerKit

struct RegistrationInfo: Codable {
    let email: String
    let password: String
    let name: String
    let isAdmin: Bool
}

/// Matches API wire type `UserPublic` for BinaryCodable type headers.
struct UserPublic: Codable {
    let id: String
    let email: String
    let name: String?
    let isAdmin: Bool
}

typealias User = UserPublic

struct LoginInfo: Codable, Sendable, Equatable {
    let email: String
    let password: String
}

public struct UpdatePasswordInfo: Codable, Sendable, Equatable {
    public let oldPassword: String
    public let newPassword: String
}


@MainActor
@Observable
final class AuthenticationViewModel {
    
    let keychain = Keychain.shared
    var user: User?
    var didSignIn = false
    
    enum Errors: Error {
        case failedRequest(Int), invalidData
    }
    
    
    func registration(email: String, password: String) async throws {
        let registration = RegistrationInfo(
            email: email,
            password: password,
            name: email,
            isAdmin: false
        )
        
        let body = try BinaryEncoder().encode(registration)
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
        let info = LoginInfo(email: email, password: password)
        
        let body = try BinaryEncoder().encode(info)
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
        
        user = token.user
        await URLSession.persistSession(accessToken: token.token, refreshToken: token.refreshToken)
        self.didSignIn = true
        try await connectMerchantWebSocketIfAdmin(accessToken: token.token)
    }

    func refreshToken() async throws {
        guard let refreshToken = await URLSession.AuthTokenStore.shared.getRefreshToken() else {
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
        let decoded = try BinaryDecoder().decode(TokenResponse.self, from: data)
        self.user = decoded.user
        await URLSession.persistSession(accessToken: decoded.token, refreshToken: decoded.refreshToken)
    }

    /// Cold start: refresh keychain session and reconnect admin merchant WS when applicable.
    func restoreSessionIfNeeded() async {
        guard await URLSession.AuthTokenStore.shared.getRefreshToken() != nil else { return }
        do {
            try await refreshToken()
            didSignIn = true
            if let access = await URLSession.AuthTokenStore.shared.getAccessToken() {
                try await connectMerchantWebSocketIfAdmin(accessToken: access)
            }
        } catch {
            logger.info("Session restore failed: \(error)")
            signOut()
        }
    }

    func signOut() {
        user = nil
        didSignIn = false
        Task {
            await URLSession.AuthTokenStore.shared.clear()
            await WebSocketClient.shared.disconnect(Constants.wsMerchantRoute)
        }
    }
    
    func updatePassword(
        email: String,
        oldPassword: String,
        newPassword: String
    ) async throws {
        let payload = UpdatePasswordInfo(oldPassword: oldPassword, newPassword: newPassword)
        let body = try BinaryEncoder().encode(payload)
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
        await URLSession.persistSession(accessToken: token.token, refreshToken: token.refreshToken)
        self.didSignIn = true
    }
    
    func deleteAccountLocally() {
        signOut()
    }

    private func connectMerchantWebSocketIfAdmin(accessToken: String) async throws {
        guard user?.isAdmin == true else { return }
        try await WebSocketClient.shared.connect(
            host: Constants.wsHost,
            port: Constants.wsPort,
            enableTLS: Constants.wsEnableTLS,
            route: Constants.wsMerchantRoute,
            headers: .init([("Authorization", "Bearer \(accessToken)")]))
        let auth = WSAuthPacket(token: accessToken, topic: "merchant")
        try await WebSocketClient.shared.sendBinary(
            BinaryEncoder().encode(auth),
            to: Constants.wsMerchantRoute)
        try await Task.sleep(until: .now + .seconds(1))
        try await WebSocketClient.shared.sendPing(
            "ping_data".data(using: .utf8)!,
            to: Constants.wsMerchantRoute)
    }
    
}

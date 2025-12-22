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
import BSON
import ConnectionManagerKit

struct RegistrationInfo: Codable {
    let email: String
    let password: String
    let name: String
    let isAdmin: Bool
}

struct User: Codable {
    let id: String
    let email: String
    let name: String?
    let role: String?
    let isAdmin: Bool
}

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
            isAdmin: true
        )
        
        let body = try BSONEncoder().encode(registration).makeData()
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
        
        let body = try BSONEncoder().encode(info).makeData()
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
        try keychain.set(token.token, forKey: "com.example.app.access-token")
        if let refreshToken = token.refreshToken {
            try keychain.set(refreshToken, forKey: "com.example.app.refresh-token")
        }
        self.didSignIn = true
        
        try await WebSocketClient.shared.connect(
            host: Constants.wsHost,
            route: "/api/ws/merchant",
            headers: .init([("Authorization", "Bearer \(token.token)")]))
        
        try await Task.sleep(until: .now + .seconds(2))
        
        try await WebSocketClient.shared.sendPing("ping_data".data(using: .utf8)!, to: "/api/auth/ws/merchant")
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
//        try await WebSocketClient.shared.connect(
//            host: Constants.wsHost,
//            route: "/api/auth/ws/merchant",
//            headers: .init([("Authorization", "Bearer \(token.token)")]))
//        try await Task.sleep(until: .now + .seconds(2))
//        try await WebSocketClient.shared.sendPing("ping_data".data(using: .utf8)!, to: "/api/auth/ws/merchant")
        
    }

    func signOut() {
        try? keychain.removeValue(forKey: "com.example.app.access-token")
        try? keychain.removeValue(forKey: "com.example.app.refresh-token")
        user = nil
        didSignIn = false
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
        try keychain.set(token.token, forKey: "com.example.app.access-token")
        if let refreshToken = token.refreshToken {
            try keychain.set(refreshToken, forKey: "com.example.app.refresh-token")
        }
        self.didSignIn = true
    }
    
    func deleteAccountLocally() {
        signOut()
    }
    
}

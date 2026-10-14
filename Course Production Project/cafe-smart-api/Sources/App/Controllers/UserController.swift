//
//  UserController.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is licensed under the MIT License.
//
//  See the LICENSE file for more information.
//
//  This file is part of the CafeSmartAPI Project

@preconcurrency import BSON
@preconcurrency import Crypto
import JWT
import MongoKitten
import Vapor

struct UserPublic: Codable, Sendable, BinaryResponseEncodable {
    let id: String
    let email: String
    let name: String?
    let isAdmin: Bool
    let venueRole: VenueRole
    let teamMemberId: String?

    init(
        id: String,
        email: String,
        name: String?,
        isAdmin: Bool,
        venueRole: VenueRole = .guest,
        teamMemberId: String? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.isAdmin = isAdmin
        self.venueRole = isAdmin ? .admin : venueRole
        self.teamMemberId = teamMemberId
    }

    static func make(from user: User) -> UserPublic {
        let admin = AdminEnv.isAdmin(user: user)
        return UserPublic(
            id: user.id,
            email: user.email,
            name: user.name,
            isAdmin: admin,
            venueRole: admin ? .admin : user.resolvedVenueRole,
            teamMemberId: user.teamMemberId)
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

struct AssignVenueRoleRequest: Content {
    var venueRole: VenueRole
    var teamMemberId: String?
}

/// Wire name matches client `RegisterInfo` for BinaryCodable type headers.
struct RegisterInfo: Content {
    let email: String
    let password: String
    let name: String?
    let isAdmin: Bool
}

@available(*, deprecated, renamed: "RegisterInfo")
typealias RegisterRequest = RegisterInfo

/// Wire name matches client `LoginInfo` for BinaryCodable type headers.
struct LoginInfo: Content {
    let email: String
    let password: String
}

@available(*, deprecated, renamed: "LoginInfo")
typealias LoginRequest = LoginInfo

struct TokenResponse: Codable, Sendable, BinaryResponseEncodable {
    let token: String
    let refreshToken: String?
    let expiresAt: Date
    let user: UserPublic
    

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

struct UserJWT: JWTPayload {
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
        case subject = "sub"
    }
    var subject: SubjectClaim
    var expiration: ExpirationClaim
    func verify(using signer: some JWTAlgorithm) throws {
        try expiration.verifyNotExpired()
    }
}

/// Wire name matches client `UpdatePasswordInfo` for BinaryCodable type headers.
struct UpdatePasswordInfo: Content {
    let oldPassword: String
    let newPassword: String
}

@available(*, deprecated, renamed: "UpdatePasswordInfo")
typealias ChangePasswordRequest = UpdatePasswordInfo

/// Wire name matches client `UpdateProfileRequest` for BinaryCodable type headers.
struct UpdateProfileRequest: Content {
    let name: String?
    let email: String?
}

actor UserController {
    // Create
    func register(req: Request) async throws -> UserPublic {
        let register = try req.content.decode(RegisterInfo.self)
        guard register.email.contains("@"), register.password.count >= 8 else {
            throw Abort(.badRequest, reason: "Invalid email or password too short")
        }
        if try await req.store.findUser(byEmail: register.email.lowercased()) != nil {
            throw Abort(.conflict, reason: "User already exists")
        }
        // Never trust client-supplied admin flags on open registration.
        // Bootstrap: emails listed in ADMIN_USERNAMES may self-register as admin.
        // Otherwise only an already-authenticated admin may create another admin.
        var grantAdmin = AdminEnv.isListedAdmin(email: register.email)
        if !grantAdmin, register.isAdmin {
            if req.storage.get(IsAdminKey.self) == true {
                grantAdmin = true
            } else if let actor = req.storage.get(UserKey.self) {
                grantAdmin = AdminEnv.isAdmin(user: actor, requestIsAdmin: true)
            }
        }
        let passwordHash = try await req.password.async.hash(register.password)
        let user = User(
            id: ObjectId().hexString,
            email: register.email.lowercased(),
            name: register.name,
            isAdmin: grantAdmin,
            venueRole: grantAdmin ? .admin : .guest,
            passwordHash: passwordHash,
            symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            createdAt: Date())
        try await req.store.createUser(user)
        try? await LoyaltyLedger.ensureAccount(req: req, userId: user.id)
        return UserPublic.make(from: user)
    }
    
    // Login -> token + public user
    func login(req: Request) async throws -> TokenResponse {
        let login = try req.content.decode(LoginInfo.self)
        guard let user = try await req.store.findUser(byEmail: login.email.lowercased()) else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        guard try await req.password.async.verify(login.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        let expirationDate = Date().addingTimeInterval(60 * 60 * 24)
        let payload = UserJWT(
            subject: .init(value: user.id), expiration: .init(value: expirationDate))
        let token = try await req.jwt.sign(payload, kid: JWTConfiguration.mldsa87Kid)
        // Create and persist a refresh token, return as base64-encoded string
        let issuedAt = Date()
        let refreshExpiry = issuedAt.addingTimeInterval(60 * 60 * 24 * 30) // 30 days
        let refreshRandom = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let refreshSecret = Data(refreshRandom).base64EncodedString()
        let refresh = RefreshToken(
            _id: user.id,
            token: refreshSecret,
            expiresAt: refreshExpiry,
            issuedAt: issuedAt
        )
        let encryptedRefresh: Data = try await req.store.createRefreshToken(
            refresh,
            symmetricKey: SymmetricKey(data: user.symmetricKey)
        )
        let refreshTokenB64 = encryptedRefresh.base64EncodedString()
        return TokenResponse(
            token: token,
            refreshToken: refreshTokenB64,
            expiresAt: expirationDate,
            user: UserPublic.make(from: user))
    }
    
    // Read list (admin — People / role assignment)
    func list(req: Request) async throws -> UsersWrapper {
        let users = try await req.store.listUsers()
        return UsersWrapper(items: users.map { UserPublic.make(from: $0) })
    }
    
    // Read single
    func get(req: Request) async throws -> UserPublic {
        guard let id = req.parameters.get("id"), let user = try await req.store.findUser(byId: id) else {
            throw Abort(.notFound)
        }
        return UserPublic.make(from: user)
    }

    /// Admin assigns venue role + optional roster link.
    func assignRole(req: Request) async throws -> UserPublic {
        guard let id = req.parameters.get("id"), var user = try await req.store.findUser(byId: id)
        else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(AssignVenueRoleRequest.self)
        if user.resolvedVenueRole == .admin || AdminEnv.isListedAdmin(email: user.email),
           body.venueRole != .admin
        {
            let admins = try await req.store.listUsers().filter {
                AdminEnv.isAdmin(user: $0) || $0.resolvedVenueRole == .admin
            }
            if admins.count <= 1 {
                throw Abort(.conflict, reason: "Cannot demote the last admin")
            }
            if AdminEnv.isListedAdmin(email: user.email) {
                throw Abort(.forbidden, reason: "ADMIN_USERNAMES bootstrap accounts stay admin")
            }
        }
        if let raw = body.teamMemberId {
            let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if link.isEmpty {
                user.teamMemberId = nil
            } else {
                let roster = try await TeamController().list(req: req).items
                guard roster.contains(where: { $0.id == link }) else {
                    throw Abort(.badRequest, reason: "Unknown teamMemberId")
                }
                let taken = try await req.store.listUsers().contains {
                    $0.id != user.id && $0.teamMemberId == link
                }
                if taken {
                    throw Abort(.conflict, reason: "teamMemberId already linked to another user")
                }
                user.teamMemberId = link
            }
        }
        user.applyVenueRole(body.venueRole)
        let updated = try await req.store.updateUser(user)
        return UserPublic.make(from: updated)
    }
    
    // Update (name/email only; not password)
    struct UserUpdateRequest: Content {
        let email: String?
        let name: String?
    }
    func update(req: Request) async throws -> UserPublic {
        guard let id = req.parameters.get("id"), var user = try await req.store.findUser(byId: id)
        else {
            throw Abort(.notFound)
        }
        try requireSelfOrAdmin(req, userId: id)
        let body = try req.content.decode(UserUpdateRequest.self)
        if let email = body.email {
            user.email = email.lowercased()
        }
        if let name = body.name {
            user.name = name
        }
        let updated = try await req.store.updateUser(user)
        return UserPublic.make(from: updated)
    }
    
    // Change password
    func changePassword(req: Request) async throws -> TokenResponse {
        guard let id = req.parameters.get("id"), var user = try await req.store.findUser(byId: id)
        else {
            throw Abort(.notFound)
        }
        try requireSelfOrAdmin(req, userId: id)
        let request = try req.content.decode(UpdatePasswordInfo.self)
        guard try await req.password.async.verify(request.oldPassword, created: user.passwordHash)
        else {
            throw Abort(.unauthorized, reason: "Old password is incorrect")
        }
        user.passwordHash = try await req.password.async.hash(request.newPassword)
        try await req.store.updatePassword(user: user)
        let expirationDate = Date().addingTimeInterval(60 * 60 * 24)
        let payload = UserJWT(
            subject: .init(value: user.id), expiration: .init(value: expirationDate))
        let token = try await req.jwt.sign(payload, kid: JWTConfiguration.mldsa87Kid)
        // Create and persist a refresh token, return as base64-encoded string
        let issuedAt = Date()
        let refreshExpiry = issuedAt.addingTimeInterval(60 * 60 * 24 * 30) // 30 days
        let refreshRandom = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let refreshSecret = Data(refreshRandom).base64EncodedString()
        let refresh = RefreshToken(
            _id: user.id,
            token: refreshSecret,
            expiresAt: refreshExpiry,
            issuedAt: issuedAt
        )
        let encryptedRefresh: Data = try await req.store.createRefreshToken(
            refresh,
            symmetricKey: SymmetricKey(data: user.symmetricKey)
        )
        let refreshTokenB64 = encryptedRefresh.base64EncodedString()
        return TokenResponse(
            token: token,
            refreshToken: refreshTokenB64,
            expiresAt: expirationDate,
            user: UserPublic.make(from: user))
    }
    
    // Logout current user (invalidate refresh tokens)
    func logout(req: Request) async throws -> HTTPStatus {
        guard let user = req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        try await req.store.removeUserTokens(user)
        return .ok
    }
    
    /// Return the authenticated user's public profile (cold-start restore).
    func me(req: Request) async throws -> UserPublic {
        guard let user = req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        return UserPublic.make(from: user)
    }

    /// Update the authenticated user's display name / email.
    func updateProfile(req: Request) async throws -> UserPublic {
        guard var user = req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        let body = try req.content.decode(UpdateProfileRequest.self)
        if let email = body.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            let lower = email.lowercased()
            if lower != user.email,
               let existing = try await req.store.findUser(byEmail: lower),
               existing.id != user.id
            {
                throw Abort(.conflict, reason: "Email already in use")
            }
            user.email = lower
        }
        if let name = body.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            user.name = name.isEmpty ? nil : name
        }
        let updated = try await req.store.updateUser(user)
        return UserPublic.make(from: updated)
    }

    // Update password for the authenticated user
    func updatePassword(req: Request) async throws -> HTTPStatus {
        guard var user = req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        let payload = try req.content.decode(UpdatePasswordInfo.self)
        guard try await req.password.async.verify(payload.oldPassword, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Old password is incorrect")
        }
        user.passwordHash = try await req.password.async.hash(payload.newPassword)
        try await req.store.updatePassword(user: user)
        // Revoke all refresh sessions after credential change.
        try await req.store.removeUserTokens(user)
        try await req.store.deleteToken(
            user.id, symmetricKey: SymmetricKey(data: user.symmetricKey))
        return .ok
    }
    
    // Delete the authenticated user's account
    func deleteAccount(req: Request) async throws -> HTTPStatus {
        guard let user =  req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        // Best effort: remove tokens then delete user
        try await req.store.removeUserTokens(user)
        try await req.store.deleteUser(id: user.id)
        return .noContent
    }
    // Delete
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try requireSelfOrAdmin(req, userId: id)
        try await req.store.deleteUser(id: id)
        return .noContent
    }
    
    // Refresh access token using the encrypted refresh token from login (rotating).
    func refreshToken(req: Request) async throws -> TokenResponse {
        guard let bearer = req.headers.bearerAuthorization,
              let encrypted = Data(base64Encoded: bearer.token)
        else {
            throw Abort(.unauthorized, reason: "Missing refresh token")
        }
        guard let user = try await req.store.findUser(refreshToken: encrypted) else {
            throw Abort(.unauthorized, reason: "Invalid refresh token")
        }
        // Rotate: invalidate the presented refresh blob before issuing a replacement.
        try await req.store.deleteRefreshToken(encrypted)

        let newExp = Date().addingTimeInterval(60 * 60 * 24)
        let newPayload = UserJWT(subject: .init(value: user.id), expiration: .init(value: newExp))
        let token = try await req.jwt.sign(newPayload, kid: JWTConfiguration.mldsa87Kid)

        let issuedAt = Date()
        let refreshExpiry = issuedAt.addingTimeInterval(60 * 60 * 24 * 30)
        let refreshRandom = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let refreshSecret = Data(refreshRandom).base64EncodedString()
        let refresh = RefreshToken(
            _id: user.id,
            token: refreshSecret,
            expiresAt: refreshExpiry,
            issuedAt: issuedAt)
        let encryptedRefresh = try await req.store.createRefreshToken(
            refresh,
            symmetricKey: SymmetricKey(data: user.symmetricKey))

        return TokenResponse(
            token: token,
            refreshToken: encryptedRefresh.base64EncodedString(),
            expiresAt: newExp,
            user: UserPublic.make(from: user))
    }

    private func requireSelfOrAdmin(_ req: Request, userId: String) throws {
        guard let actor = req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        let isAdmin = req.storage.get(IsAdminKey.self) == true || actor.isAdmin
        guard isAdmin || actor.id == userId else {
            throw Abort(.forbidden, reason: "Not allowed to modify this user")
        }
    }
}

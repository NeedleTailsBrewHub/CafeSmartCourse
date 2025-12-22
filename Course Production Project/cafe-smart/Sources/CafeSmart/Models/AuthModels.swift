//
//  AuthModels.swift
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

#if SKIP
import SkipFoundation
#else
import Foundation
#endif

public struct RegisterInfo: Codable, Sendable, Equatable {
    public let email: String
    public let password: String
    public let name: String?
    public let isAdmin: Bool
}

public struct LoginInfo: Codable, Sendable, Equatable {
    public let email: String
    public let password: String
}

public struct User: Codable, Sendable, Equatable {
    public let id: String
    public let email: String
    public let name: String?
    public let role: String?
    public let isAdmin: Bool
}

public struct TokenResponse: Codable, Sendable, Equatable {
    public let token: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let user: User
}

public struct UpdatePasswordInfo: Codable, Sendable, Equatable {
    public let oldPassword: String
    public let newPassword: String
}



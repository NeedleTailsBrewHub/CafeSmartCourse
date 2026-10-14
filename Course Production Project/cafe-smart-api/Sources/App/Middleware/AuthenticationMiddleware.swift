//
//  AuthenticationMiddleware+Extension.swift
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

import JWT
import Vapor

/// Middleware for authenticating API requests in the NeedleTail system.
///
/// Validates `Authorization: Bearer <JWT>` (MLDSA87) and attaches the user to request storage.
struct AuthenticationMiddleware: AsyncMiddleware {

  func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
    guard let authHeader = request.headers.bearerAuthorization else {
      return Response(status: .unauthorized)
    }

    let user: User
    do {
      let verified = try await request.jwt.verify(authHeader.token, as: UserJWT.self)
      guard let found = try await request.store.findUser(byId: verified.subject.value) else {
        return Response(status: .unauthorized)
      }
      user = found
    } catch {
      // Invalid/expired tokens must not surface as 500s.
      // Do not wrap `next.respond` — controller Aborts must propagate.
      return Response(status: .unauthorized)
    }

    let isAdmin = AdminEnv.isAdmin(user: user)
    let venueRole = RoleGate.venueRole(for: user, requestIsAdmin: isAdmin)
    await request.storage.setWithAsyncShutdown(UserKey.self, to: user)
    await request.storage.setWithAsyncShutdown(IsAdminKey.self, to: isAdmin)
    await request.storage.setWithAsyncShutdown(VenueRoleKey.self, to: venueRole)
    return try await next.respond(to: request)
  }
}

/// Storage key for the authenticated user.
///
/// This key is used to store the complete User object of the
/// authenticated user in the request storage.
struct UserKey: StorageKey {
  typealias Value = User
}

/// Storage key for the server admin flag.
///
/// This key is used to store whether the authenticated user
/// has server admin privileges in the request storage.
struct IsAdminKey: StorageKey {
  typealias Value = Bool
}

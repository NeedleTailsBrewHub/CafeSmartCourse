//
//  AdminMiddleware+Extension.swift
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

/// Middleware for enforcing admin-only access to API endpoints.
///
/// This middleware extends the AuthenticationMiddleware to add admin
/// authorization checks. It verifies that the authenticated user has
/// admin privileges before allowing access to protected endpoints.
struct AdminMiddleware: AsyncMiddleware {

  func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
    // Already marked as admin upstream (DB flag or ADMIN_USERNAMES).
    if request.storage.get(IsAdminKey.self) == true {
      return try await next.respond(to: request)
    }

    // Require authenticated user in storage
    guard let user = request.storage.get(UserKey.self) else {
      return Response(
        status: .custom(code: 996, reasonPhrase: "Admin Check Failed - User Not Found"))
    }

    // Re-check env list at request time (getenv; survives setenv in tests).
    if AdminEnv.isListedAdmin(email: user.email) {
      await request.storage.setWithAsyncShutdown(IsAdminKey.self, to: true)
      return try await next.respond(to: request)
    } else {
      return Response(status: .custom(code: 995, reasonPhrase: "Admin Access Required"))
    }
  }
}

/// Extension to make it easy to check admin status in controllers.
extension Request {
  var isAdmin: Bool {
    get async { storage.get(IsAdminKey.self) ?? false }
  }
}

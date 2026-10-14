//
//  AuthenticationMiddleware.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
import Vapor

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

        await request.storage.setWithAsyncShutdown(UserKey.self, to: user)
        await request.storage.setWithAsyncShutdown(IsAdminKey.self, to: user.isAdmin)
        return try await next.respond(to: request)
    }
}

struct UserKey: StorageKey {
    typealias Value = User
}

struct IsAdminKey: StorageKey {
    typealias Value = Bool
}

//
//  AuthenticationMiddleware.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
import Vapor

struct AuthenticationMiddleware: AsyncMiddleware {
    
    
    func respond(to request: Vapor.Request, chainingTo next: any Vapor.AsyncResponder) async throws -> Vapor.Response {
        guard let authHeader = request.headers.bearerAuthorization else {
            return Response(status: .unauthorized)
        }
        
        let verified = try await request.jwt.verify(authHeader.token, as: UserJWT.self)
        
        guard let user = try await request.store.findUser(byId: verified.subject.value) else {
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

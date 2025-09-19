//
//  AdminMiddleware.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
//

import Vapor

struct AdminMiddleware: AsyncMiddleware {
    func respond(to request: Vapor.Request, chainingTo next: any Vapor.AsyncResponder) async throws -> Vapor.Response {
        if request.storage.get(IsAdminKey.self) == true {
            return try await next.respond(to: request)
        } else {
            return Response(status: .unauthorized)
        }
        
//        guard let user = request.storage.get(UserKey.self) else {
//          return Response(
//            status: .custom(code: 996, reasonPhrase: "Admin Check Failed - User Not Found"))
//        }
//        
//        return try await next.respond(to: request)
    }
}

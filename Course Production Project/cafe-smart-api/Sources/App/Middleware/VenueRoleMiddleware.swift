//
//  VenueRoleMiddleware.swift
//  CafeSmartAPI
//
//  Requires authenticated user to meet a minimum VenueRole.
//

import Vapor

struct VenueRoleMiddleware: AsyncMiddleware {
    let minimum: VenueRole

    init(minimum: VenueRole) {
        self.minimum = minimum
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let user = request.storage.get(UserKey.self) else {
            return Response(
                status: .custom(code: 996, reasonPhrase: "Role Check Failed - User Not Found"))
        }
        let role: VenueRole
        if let stored = request.storage.get(VenueRoleKey.self) {
            role = stored
        } else {
            role = RoleGate.venueRole(
                for: user, requestIsAdmin: request.storage.get(IsAdminKey.self) == true)
            await request.storage.setWithAsyncShutdown(VenueRoleKey.self, to: role)
        }
        guard role.meets(minimum) else {
            return Response(status: .custom(code: 995, reasonPhrase: "Insufficient role"))
        }
        return try await next.respond(to: request)
    }
}

struct VenueRoleKey: StorageKey {
    typealias Value = VenueRole
}

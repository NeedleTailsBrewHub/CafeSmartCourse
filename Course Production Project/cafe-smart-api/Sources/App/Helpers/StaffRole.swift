//
//  StaffRole.swift
//  CafeSmartAPI
//
//  Persisted venue roles for merchant access control.
//

import Vapor

/// Auth role stored on `User` (distinct from free-text `TeamMember.role` job title).
public enum VenueRole: String, Codable, Sendable, CaseIterable, Equatable, Comparable {
    case guest
    case staff
    case manager
    case admin

    private var rank: Int {
        switch self {
        case .guest: return 0
        case .staff: return 1
        case .manager: return 2
        case .admin: return 3
        }
    }

    public static func < (lhs: VenueRole, rhs: VenueRole) -> Bool {
        lhs.rank < rhs.rank
    }

    /// True when this role meets or exceeds `minimum`.
    public func meets(_ minimum: VenueRole) -> Bool {
        self >= minimum
    }
}

/// Legacy staff-role labels kept for LoyaltyController / older call sites.
public enum StaffRole: String, Codable, Sendable, CaseIterable, Equatable {
    case owner
    case manager
    case barista
    case cashier
    case guest
}

enum RoleGate {
    /// Effective persisted + env-boosted venue role.
    static func venueRole(for user: User, requestIsAdmin: Bool = false) -> VenueRole {
        if AdminEnv.isAdmin(user: user, requestIsAdmin: requestIsAdmin) {
            return .admin
        }
        return user.resolvedVenueRole
    }

    static func venueRole(req: Request) throws -> VenueRole {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        if let stored = req.storage.get(VenueRoleKey.self) {
            return stored
        }
        let requestIsAdmin = req.storage.get(IsAdminKey.self) == true
        return venueRole(for: user, requestIsAdmin: requestIsAdmin)
    }

    /// Floor / merchant operators (staff, manager, admin) — not guest customers.
    static func isMerchantFloor(for user: User, requestIsAdmin: Bool = false) -> Bool {
        venueRole(for: user, requestIsAdmin: requestIsAdmin).meets(.staff)
    }

    static func isMerchantFloor(req: Request) -> Bool {
        guard let user = req.storage.get(UserKey.self) else { return false }
        if let stored = req.storage.get(VenueRoleKey.self) {
            return stored.meets(.staff)
        }
        let requestIsAdmin = req.storage.get(IsAdminKey.self) == true
        return isMerchantFloor(for: user, requestIsAdmin: requestIsAdmin)
    }

    static func require(req: Request, minimum: VenueRole) throws {
        let have = try venueRole(req: req)
        guard have.meets(minimum) else {
            throw Abort(.custom(code: 995, reasonPhrase: "Insufficient role"))
        }
    }

    /// Map venue role → legacy StaffRole set (tests + Loyalty).
    static func roles(for user: User, requestIsAdmin: Bool = false) -> Set<StaffRole> {
        switch venueRole(for: user, requestIsAdmin: requestIsAdmin) {
        case .admin:
            return [.owner, .manager, .barista, .cashier]
        case .manager:
            return [.manager, .barista, .cashier]
        case .staff:
            return [.barista, .cashier]
        case .guest:
            return [.guest]
        }
    }

    static func roles(req: Request) throws -> Set<StaffRole> {
        guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
        let requestIsAdmin = req.storage.get(IsAdminKey.self) == true
        return roles(for: user, requestIsAdmin: requestIsAdmin)
    }

    static func require(req: Request, anyOf needed: Set<StaffRole>) throws {
        let have = try roles(req: req)
        guard !have.isDisjoint(with: needed) else {
            throw Abort(.forbidden, reason: "Missing required role")
        }
    }

    static func requireStaff(req: Request) throws {
        try require(req: req, minimum: .staff)
    }

    static func requireManager(req: Request) throws {
        try require(req: req, minimum: .manager)
    }

    static func requireAdmin(req: Request) throws {
        try require(req: req, minimum: .admin)
    }
}

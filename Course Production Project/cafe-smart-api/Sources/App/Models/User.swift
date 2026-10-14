//
//  User.swift
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


import Foundation
import Vapor

public struct User: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var email: String
	public var name: String?
	public var isAdmin: Bool
	/// Persisted venue role. Missing on older docs → derived from `isAdmin`.
	public var venueRole: VenueRole
	/// Optional link to a `TeamMember` for self clock-in.
	public var teamMemberId: String?
	public var passwordHash: String
	public var symmetricKey: Data
	public var createdAt: Date
	public var stripeCustomerId: String? = nil

	public init(
		id: String,
		email: String,
		name: String? = nil,
		isAdmin: Bool,
		venueRole: VenueRole? = nil,
		teamMemberId: String? = nil,
		passwordHash: String,
		symmetricKey: Data,
		createdAt: Date,
		stripeCustomerId: String? = nil
	) {
		self.id = id
		self.email = email
		self.name = name
		let role = venueRole ?? (isAdmin ? .admin : .guest)
		self.venueRole = role
		self.isAdmin = isAdmin || role == .admin
		self.teamMemberId = teamMemberId
		self.passwordHash = passwordHash
		self.symmetricKey = symmetricKey
		self.createdAt = createdAt
		self.stripeCustomerId = stripeCustomerId
	}

	enum CodingKeys: String, CodingKey {
		case id, email, name, isAdmin, venueRole, teamMemberId
		case passwordHash, symmetricKey, createdAt, stripeCustomerId
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decode(String.self, forKey: .id)
		email = try c.decode(String.self, forKey: .email)
		name = try c.decodeIfPresent(String.self, forKey: .name)
		let isAdminFlag = try c.decode(Bool.self, forKey: .isAdmin)
		if let role = try c.decodeIfPresent(VenueRole.self, forKey: .venueRole) {
			venueRole = role
		} else {
			venueRole = isAdminFlag ? .admin : .guest
		}
		isAdmin = isAdminFlag || venueRole == .admin
		teamMemberId = try c.decodeIfPresent(String.self, forKey: .teamMemberId)
		passwordHash = try c.decode(String.self, forKey: .passwordHash)
		symmetricKey = try c.decode(Data.self, forKey: .symmetricKey)
		createdAt = try c.decode(Date.self, forKey: .createdAt)
		stripeCustomerId = try c.decodeIfPresent(String.self, forKey: .stripeCustomerId)
	}

	/// Role used for authorization after env-admin boost is applied separately.
	public var resolvedVenueRole: VenueRole {
		if isAdmin { return .admin }
		return venueRole
	}

	/// Keep `isAdmin` wire flag aligned with venue role.
	public mutating func applyVenueRole(_ role: VenueRole) {
		venueRole = role
		isAdmin = role == .admin
	}

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

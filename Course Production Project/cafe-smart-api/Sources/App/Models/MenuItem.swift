//
//  MenuItem.swift
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

/// Wire name matches client `Allergen` for BinaryCodable type headers.
public enum Allergen: String, Codable, Sendable, CaseIterable, Equatable {
	case milk, eggs, gluten, nuts, soy, sesame, shellfish, fish
}

/// Wire name matches client `MenuSizeOption`.
public struct MenuSizeOption: Content, Sendable, Equatable {
	public var name: String
	public var priceDeltaCents: Int

	public init(name: String, priceDeltaCents: Int) {
		self.name = name
		self.priceDeltaCents = priceDeltaCents
	}
}

public struct MenuItem: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var name: String
	public var description: String?
	public var priceCents: Int
	public var isAvailable: Bool
	public var category: String?
	public var createdAt: Date
	public var subcategory: String? = nil
	public var prepSeconds: Int? = nil
	public var prepStation: String? = nil
	public var allergens: [Allergen]? = nil
	public var tagIds: [String]? = nil
	public var sizeOptions: [MenuSizeOption]? = nil
	public var deletedAt: Date? = nil
	public var updatedAt: Date? = nil
	public var updatedByUserId: String? = nil
	/// When true (default if nil), paid units earn loyalty points while the program is on.
	public var loyaltyEarnEnabled: Bool? = nil
	/// Points required to make one unit free at checkout. nil/0 = not redeemable.
	public var loyaltyRedeemPoints: Int? = nil
	/// Absolute URL or API-relative path (e.g. `/menu-images/latte.png`).
	public var imageURL: String? = nil
	/// Object storage key for replace/delete (`menu/{id}/{uuid}.ext`).
	public var imageMediaKey: String? = nil

	public var earnsLoyaltyPoints: Bool { loyaltyEarnEnabled != false }
	public var redeemPointsCost: Int { max(0, loyaltyRedeemPoints ?? 0) }

	public init(
		id: String,
		name: String,
		description: String? = nil,
		priceCents: Int,
		isAvailable: Bool,
		category: String? = nil,
		createdAt: Date,
		subcategory: String? = nil,
		sizeOptions: [MenuSizeOption]? = nil,
		prepSeconds: Int? = nil,
		prepStation: String? = nil,
		allergens: [Allergen]? = nil,
		tagIds: [String]? = nil,
		deletedAt: Date? = nil,
		updatedAt: Date? = nil,
		updatedByUserId: String? = nil,
		loyaltyEarnEnabled: Bool? = nil,
		loyaltyRedeemPoints: Int? = nil,
		imageURL: String? = nil,
		imageMediaKey: String? = nil
	) {
		self.id = id
		self.name = name
		self.description = description
		self.priceCents = priceCents
		self.isAvailable = isAvailable
		self.category = category
		self.createdAt = createdAt
		self.subcategory = subcategory
		self.sizeOptions = sizeOptions
		self.prepSeconds = prepSeconds
		self.prepStation = prepStation
		self.allergens = allergens
		self.tagIds = tagIds
		self.deletedAt = deletedAt
		self.updatedAt = updatedAt
		self.updatedByUserId = updatedByUserId
		self.loyaltyEarnEnabled = loyaltyEarnEnabled
		self.loyaltyRedeemPoints = loyaltyRedeemPoints
		self.imageURL = imageURL
		self.imageMediaKey = imageMediaKey
	}

	public func encodeResponse(for request: Request) async throws -> Response {
		try binaryEncodedResponse()
	}
}

public struct MenuItemsWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var items: [MenuItem]

	public func encodeResponse(for request: Request) async throws -> Response {
		try binaryEncodedResponse()
	}
}

/// Wire name matches client `CreateMenuItemRequest`.
public struct CreateMenuItemRequest: Content, Sendable {
	public var name: String
	public var description: String?
	public var priceCents: Int
	public var isAvailable: Bool
	public var category: String?
	public var subcategory: String?
	public var sizeOptions: [MenuSizeOption]?
	public var prepSeconds: Int?
	public var prepStation: String?
	public var allergens: [Allergen]?
	public var tagIds: [String]?
	public var loyaltyEarnEnabled: Bool?
	public var loyaltyRedeemPoints: Int?
	public var imageURL: String?

	public init(
		name: String,
		description: String? = nil,
		priceCents: Int,
		isAvailable: Bool,
		category: String? = nil,
		subcategory: String? = nil,
		sizeOptions: [MenuSizeOption]? = nil,
		prepSeconds: Int? = nil,
		prepStation: String? = nil,
		allergens: [Allergen]? = nil,
		tagIds: [String]? = nil,
		loyaltyEarnEnabled: Bool? = nil,
		loyaltyRedeemPoints: Int? = nil,
		imageURL: String? = nil
	) {
		self.name = name
		self.description = description
		self.priceCents = priceCents
		self.isAvailable = isAvailable
		self.category = category
		self.subcategory = subcategory
		self.sizeOptions = sizeOptions
		self.prepSeconds = prepSeconds
		self.prepStation = prepStation
		self.allergens = allergens
		self.tagIds = tagIds
		self.loyaltyEarnEnabled = loyaltyEarnEnabled
		self.loyaltyRedeemPoints = loyaltyRedeemPoints
		self.imageURL = imageURL
	}
}

@available(*, deprecated, renamed: "CreateMenuItemRequest")
public typealias MenuItemCreate = CreateMenuItemRequest

/// Wire name matches client `UpdateMenuItemRequest`.
public struct UpdateMenuItemRequest: Content, Sendable {
	public var name: String?
	public var description: String?
	public var priceCents: Int?
	public var isAvailable: Bool?
	public var category: String?
	public var subcategory: String?
	public var sizeOptions: [MenuSizeOption]?
	public var prepSeconds: Int?
	public var prepStation: String?
	public var allergens: [Allergen]?
	public var tagIds: [String]?
	public var loyaltyEarnEnabled: Bool?
	public var loyaltyRedeemPoints: Int?
	public var imageURL: String?

	public init(
		name: String? = nil,
		description: String? = nil,
		priceCents: Int? = nil,
		isAvailable: Bool? = nil,
		category: String? = nil,
		subcategory: String? = nil,
		sizeOptions: [MenuSizeOption]? = nil,
		prepSeconds: Int? = nil,
		prepStation: String? = nil,
		allergens: [Allergen]? = nil,
		tagIds: [String]? = nil,
		loyaltyEarnEnabled: Bool? = nil,
		loyaltyRedeemPoints: Int? = nil,
		imageURL: String? = nil
	) {
		self.name = name
		self.description = description
		self.priceCents = priceCents
		self.isAvailable = isAvailable
		self.category = category
		self.subcategory = subcategory
		self.sizeOptions = sizeOptions
		self.prepSeconds = prepSeconds
		self.prepStation = prepStation
		self.allergens = allergens
		self.tagIds = tagIds
		self.loyaltyEarnEnabled = loyaltyEarnEnabled
		self.loyaltyRedeemPoints = loyaltyRedeemPoints
		self.imageURL = imageURL
	}
}

/// Admin bulk menu operations.
public struct MenuBulkRequest: Content, Sendable {
	public var ids: [String]
	public var action: String
	public var isAvailable: Bool?

	public init(ids: [String], action: String, isAvailable: Bool? = nil) {
		self.ids = ids
		self.action = action
		self.isAvailable = isAvailable
	}
}

@available(*, deprecated, renamed: "UpdateMenuItemRequest")
public typealias MenuItemUpdate = UpdateMenuItemRequest

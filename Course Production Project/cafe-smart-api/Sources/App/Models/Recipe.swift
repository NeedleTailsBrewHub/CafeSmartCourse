//
//  Recipe.swift
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

public struct RecipeComponent: Codable, Sendable, Equatable {
	public var sku: String
	public var unitsPerItem: Double
	public var wastageRate: Double?

	public init(sku: String, unitsPerItem: Double, wastageRate: Double? = nil) {
		self.sku = sku
		self.unitsPerItem = unitsPerItem
		self.wastageRate = wastageRate
	}
}

public struct Recipe: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var menuItemId: String
	public var components: [RecipeComponent]
	public var createdAt: Date

	public init(id: String, menuItemId: String, components: [RecipeComponent], createdAt: Date) {
		self.id = id
		self.menuItemId = menuItemId
		self.components = components
		self.createdAt = createdAt
	}

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

public struct RecipesWrapper: Content, Sendable, Equatable, BinaryResponseEncodable {
    public var items: [Recipe]

    public func encodeResponse(for request: Request) async throws -> Response {
        try binaryEncodedResponse()
    }
}

/// Wire name must match VenueSmartCore `CreateRecipeRequest`.
public struct CreateRecipeRequest: Content, Sendable, Equatable {
	public var menuItemId: String
	public var components: [RecipeComponent]

	public init(menuItemId: String, components: [RecipeComponent]) {
		self.menuItemId = menuItemId
		self.components = components
	}
}

/// Wire name must match VenueSmartCore `UpdateRecipeRequest`.
public struct UpdateRecipeRequest: Content, Sendable, Equatable {
	public var components: [RecipeComponent]?

	public init(components: [RecipeComponent]?) {
		self.components = components
	}
}



//
//  MenuItem.swift
//  CafeSmart
//
//  Created by NeedleTails on 8/19/25
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmart Project
//

#if SKIP
import SkipFoundation
#else
import Foundation
#endif

public enum Allergen: String, Codable, Sendable, CaseIterable, Equatable {
    case milk, eggs, gluten, nuts, soy, sesame, shellfish, fish
}

public struct MenuSizeOption: Codable, Sendable, Equatable {
    public let name: String
    public let priceDeltaCents: Int
    
    public init(name: String, priceDeltaCents: Int) {
        self.name = name
        self.priceDeltaCents = priceDeltaCents
    }
}

public struct MenuItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var description: String?
    public var priceCents: Int
    public var isAvailable: Bool
    public var category: String?
    public var createdAt: Date
    
    // Optional extensions for real-world cafes
    public var subcategory: String? = nil
    public var sizeOptions: [MenuSizeOption]? = nil
    public var prepSeconds: Int? = nil
    public var prepStation: String? = nil
    public var allergens: [Allergen]? = nil
    
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
        allergens: [Allergen]? = nil
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
    }
}


public struct MenuItemsWrapper: Codable, Sendable, Equatable {
    public let items: [MenuItem]
}


public struct CreateMenuItemRequest: Codable, Sendable, Equatable {
    public var name: String
    public var description: String?
    public var priceCents: Int
    public var isAvailable: Bool
    public var category: String?
    // Optional extensions
    public var subcategory: String?
    public var sizeOptions: [MenuSizeOption]?
    public var prepSeconds: Int?
    public var prepStation: String?
    public var allergens: [Allergen]?

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
        allergens: [Allergen]? = nil
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
    }
}

// For now, mirror create; server may treat missing fields as unchanged
public struct UpdateMenuItemRequest: Codable, Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var priceCents: Int?
    public var isAvailable: Bool?
    public var category: String?
    // Optional extensions
    public var subcategory: String?
    public var sizeOptions: [MenuSizeOption]?
    public var prepSeconds: Int?
    public var prepStation: String?
    public var allergens: [Allergen]?

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
        allergens: [Allergen]? = nil
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
    }
}



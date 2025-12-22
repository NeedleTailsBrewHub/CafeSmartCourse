//
//  MenuRequests.swift
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



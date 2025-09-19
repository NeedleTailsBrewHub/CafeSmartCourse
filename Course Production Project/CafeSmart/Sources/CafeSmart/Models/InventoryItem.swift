//
//  InventoryItem.swift
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

public enum StorageType: String, Codable, Sendable, CaseIterable, Equatable {
    case ambient, refrigerated, frozen
}

public struct InventoryItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sku: String
    public var name: String
    public var quantity: Int
    public var reorderThreshold: Int
    public var unit: String
    public var supplier: String?

    // Additional optional fields for thorough inventory management
    public var storage: StorageType? = nil
    public var shelfLifeDays: Int? = nil
    public var leadTimeDays: Int? = nil
    public var parLevel: Int? = nil
    public var reorderQuantity: Int? = nil
    public var costPerUnitCents: Int? = nil
    public var barcode: String? = nil
    public var supplierSku: String? = nil
    public var safetyStock: Int? = nil
    public var reservedQuantity: Int? = nil

    public init(
        id: String,
        sku: String,
        name: String,
        quantity: Int,
        reorderThreshold: Int,
        unit: String,
        supplier: String? = nil,
        storage: StorageType? = nil,
        shelfLifeDays: Int? = nil,
        leadTimeDays: Int? = nil,
        parLevel: Int? = nil,
        reorderQuantity: Int? = nil,
        costPerUnitCents: Int? = nil,
        barcode: String? = nil,
        supplierSku: String? = nil,
        safetyStock: Int? = nil,
        reservedQuantity: Int? = nil
    ) {
        self.id = id
        self.sku = sku
        self.name = name
        self.quantity = quantity
        self.reorderThreshold = reorderThreshold
        self.unit = unit
        self.supplier = supplier
        self.storage = storage
        self.shelfLifeDays = shelfLifeDays
        self.leadTimeDays = leadTimeDays
        self.parLevel = parLevel
        self.reorderQuantity = reorderQuantity
        self.costPerUnitCents = costPerUnitCents
        self.barcode = barcode
        self.supplierSku = supplierSku
        self.safetyStock = safetyStock
        self.reservedQuantity = reservedQuantity
    }
}



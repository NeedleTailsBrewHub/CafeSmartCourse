//
//  InventoryRequests.swift
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

public struct CreateInventoryItemRequest: Codable, Sendable, Equatable {
    public var sku: String
    public var name: String
    public var quantity: Int
    public var reorderThreshold: Int
    public var unit: String
    public var supplier: String?
    // Optional
    public var storage: StorageType?
    public var shelfLifeDays: Int?
    public var leadTimeDays: Int?
    public var parLevel: Int?
    public var reorderQuantity: Int?
    public var costPerUnitCents: Int?
    public var barcode: String?
    public var supplierSku: String?
    public var safetyStock: Int?
    public var reservedQuantity: Int?

    public init(
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

public struct UpdateInventoryItemRequest: Codable, Sendable, Equatable {
    public var sku: String?
    public var name: String?
    public var quantity: Int?
    public var reorderThreshold: Int?
    public var unit: String?
    public var supplier: String?
    // Optional
    public var storage: StorageType?
    public var shelfLifeDays: Int?
    public var leadTimeDays: Int?
    public var parLevel: Int?
    public var reorderQuantity: Int?
    public var costPerUnitCents: Int?
    public var barcode: String?
    public var supplierSku: String?
    public var safetyStock: Int?
    public var reservedQuantity: Int?

    public init(
        sku: String? = nil,
        name: String? = nil,
        quantity: Int? = nil,
        reorderThreshold: Int? = nil,
        unit: String? = nil,
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



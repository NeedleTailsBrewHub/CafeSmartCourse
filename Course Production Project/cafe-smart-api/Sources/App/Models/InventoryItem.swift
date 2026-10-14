//
//  InventoryItem.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

public struct InventoryItem: Content, Sendable, Equatable, BinaryResponseEncodable {
	public var id: String
	public var sku: String
	public var name: String
	public var quantity: Int
	public var reorderThreshold: Int
	public var unit: String
	public var supplier: String?

	public var storage: StorageType? = nil
	public var shelfLifeDays: Int? = nil
	public var leadTimeDays: Int? = nil
	public var safetyStock: Int? = nil
	public var parLevel: Int? = nil
	public var reorderQuantity: Int? = nil
	public var tagIds: [String]? = nil
	public var deletedAt: Date? = nil
	public var updatedAt: Date? = nil
	public var updatedByUserId: String? = nil
	/// Unit cost for COGS / restock spend (cents).
	public var costPerUnitCents: Int? = nil

	public enum StorageType: String, Codable, Sendable, Equatable {
		case ambient, refrigerated, frozen
	}

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
		safetyStock: Int? = nil,
		parLevel: Int? = nil,
		reorderQuantity: Int? = nil,
		tagIds: [String]? = nil,
		deletedAt: Date? = nil,
		updatedAt: Date? = nil,
		updatedByUserId: String? = nil,
		costPerUnitCents: Int? = nil
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
		self.safetyStock = safetyStock
		self.parLevel = parLevel
		self.reorderQuantity = reorderQuantity
		self.tagIds = tagIds
		self.deletedAt = deletedAt
		self.updatedAt = updatedAt
		self.updatedByUserId = updatedByUserId
		self.costPerUnitCents = costPerUnitCents
	}

	public func encodeResponse(for request: Request) async throws -> Response {
		try binaryEncodedResponse()
	}
}

public struct CreateInventoryItemRequest: Content, Sendable {
	public var sku: String
	public var name: String
	public var quantity: Int
	public var reorderThreshold: Int
	public var unit: String
	public var supplier: String?
	public var storage: InventoryItem.StorageType?
	public var shelfLifeDays: Int?
	public var leadTimeDays: Int?
	public var safetyStock: Int?
	public var parLevel: Int?
	public var reorderQuantity: Int?
	public var tagIds: [String]?
	public var costPerUnitCents: Int?

	public init(
		sku: String,
		name: String,
		quantity: Int,
		reorderThreshold: Int,
		unit: String,
		supplier: String? = nil,
		storage: InventoryItem.StorageType? = nil,
		shelfLifeDays: Int? = nil,
		leadTimeDays: Int? = nil,
		safetyStock: Int? = nil,
		parLevel: Int? = nil,
		reorderQuantity: Int? = nil,
		tagIds: [String]? = nil,
		costPerUnitCents: Int? = nil
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
		self.safetyStock = safetyStock
		self.parLevel = parLevel
		self.reorderQuantity = reorderQuantity
		self.tagIds = tagIds
		self.costPerUnitCents = costPerUnitCents
	}
}

public struct UpdateInventoryItemRequest: Content, Sendable {
	public var name: String?
	public var quantity: Int?
	public var reorderThreshold: Int?
	public var unit: String?
	public var supplier: String?
	public var storage: InventoryItem.StorageType?
	public var shelfLifeDays: Int?
	public var leadTimeDays: Int?
	public var safetyStock: Int?
	public var parLevel: Int?
	public var reorderQuantity: Int?
	public var tagIds: [String]?
	public var costPerUnitCents: Int?

	public init(
		name: String? = nil,
		quantity: Int? = nil,
		reorderThreshold: Int? = nil,
		unit: String? = nil,
		supplier: String? = nil,
		storage: InventoryItem.StorageType? = nil,
		shelfLifeDays: Int? = nil,
		leadTimeDays: Int? = nil,
		safetyStock: Int? = nil,
		parLevel: Int? = nil,
		reorderQuantity: Int? = nil,
		tagIds: [String]? = nil,
		costPerUnitCents: Int? = nil
	) {
		self.name = name
		self.quantity = quantity
		self.reorderThreshold = reorderThreshold
		self.unit = unit
		self.supplier = supplier
		self.storage = storage
		self.shelfLifeDays = shelfLifeDays
		self.leadTimeDays = leadTimeDays
		self.safetyStock = safetyStock
		self.parLevel = parLevel
		self.reorderQuantity = reorderQuantity
		self.tagIds = tagIds
		self.costPerUnitCents = costPerUnitCents
	}
}

/// Admin bulk inventory operations.
public struct InventoryBulkRequest: Content, Sendable {
	public var ids: [String]
	public var action: String
	public var quantityDelta: Int?

	public init(ids: [String], action: String, quantityDelta: Int? = nil) {
		self.ids = ids
		self.action = action
		self.quantityDelta = quantityDelta
	}
}

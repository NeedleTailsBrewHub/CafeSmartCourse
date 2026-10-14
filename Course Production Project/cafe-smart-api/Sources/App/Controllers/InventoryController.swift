//
//  InventoryController.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Vapor

actor InventoryController {
	typealias InventoryItemCreate = CreateInventoryItemRequest
	typealias InventoryItemUpdate = UpdateInventoryItemRequest

	func list(req: Request) async throws -> PaginatedInventoryItems {
		let filter = try InventoryListFilter.from(req: req)
		let page = try await req.store.pageInventory(filter: filter)
		return PaginatedInventoryItems(items: page.items, page: page.page)
	}

	func create(req: Request) async throws -> InventoryItem {
		let body = try req.content.decode(CreateInventoryItemRequest.self)
		guard !body.sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw Abort(.badRequest, reason: "SKU required")
		}
		guard !body.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw Abort(.badRequest, reason: "Name required")
		}
		guard body.quantity >= 0, body.reorderThreshold >= 0 else {
			throw Abort(.badRequest, reason: "quantity and reorderThreshold must be >= 0")
		}
		let existing = try await req.store.listInventory()
		if existing.contains(where: {
			$0.sku.lowercased() == body.sku.lowercased() && $0.deletedAt == nil
		}) {
			throw Abort(.conflict, reason: "SKU already exists")
		}
		let tagIds = try await TagValidation.validateTagIds(store: req.store, tagIds: body.tagIds)
		let userId = req.storage.get(UserKey.self)?.id
		let now = Date()
		let model = InventoryItem(
			id: ObjectId().hexString,
			sku: body.sku,
			name: body.name,
			quantity: body.quantity,
			reorderThreshold: body.reorderThreshold,
			unit: body.unit,
			supplier: body.supplier,
			storage: body.storage,
			shelfLifeDays: body.shelfLifeDays,
			leadTimeDays: body.leadTimeDays,
			safetyStock: body.safetyStock,
			parLevel: body.parLevel,
			reorderQuantity: body.reorderQuantity,
			tagIds: tagIds.isEmpty ? nil : tagIds,
			updatedAt: now,
			updatedByUserId: userId,
			costPerUnitCents: body.costPerUnitCents)
		let created = try await req.store.create(inventoryItem: model)
		try await AuditService.write(
			req: req, entityType: "inventory", entityId: created.id, action: "create",
			summary: created.sku)
		return created
	}

	func get(req: Request) async throws -> InventoryItem {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard let item = try await req.store.findInventory(by: id) else { throw Abort(.notFound) }
		return item
	}

	func update(req: Request) async throws -> InventoryItem {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		let body = try req.content.decode(UpdateInventoryItemRequest.self)
		guard var model = try await req.store.findInventory(by: id) else { throw Abort(.notFound) }
		if let name = body.name { model.name = name }
		if let qty = body.quantity {
			guard qty >= 0 else { throw Abort(.badRequest, reason: "quantity must be >= 0") }
			model.quantity = qty
		}
		if let threshold = body.reorderThreshold {
			guard threshold >= 0 else {
				throw Abort(.badRequest, reason: "reorderThreshold must be >= 0")
			}
			model.reorderThreshold = threshold
		}
		if let unit = body.unit { model.unit = unit }
		if let supplier = body.supplier { model.supplier = supplier }
		if let storage = body.storage { model.storage = storage }
		if let shelfLifeDays = body.shelfLifeDays { model.shelfLifeDays = shelfLifeDays }
		if let leadTimeDays = body.leadTimeDays { model.leadTimeDays = leadTimeDays }
		if let safetyStock = body.safetyStock { model.safetyStock = safetyStock }
		if let parLevel = body.parLevel { model.parLevel = parLevel }
		if let reorderQuantity = body.reorderQuantity { model.reorderQuantity = reorderQuantity }
		if let cost = body.costPerUnitCents { model.costPerUnitCents = cost }
		if body.tagIds != nil {
			model.tagIds = try await TagValidation.validateTagIds(
				store: req.store, tagIds: body.tagIds, existingTagIds: model.tagIds)
		}
		model.updatedAt = Date()
		model.updatedByUserId = req.storage.get(UserKey.self)?.id
		let updated = try await req.store.update(inventoryItem: model)
		try await AuditService.write(
			req: req, entityType: "inventory", entityId: updated.id, action: "update",
			summary: updated.sku)
		return updated
	}

	func delete(req: Request) async throws -> HTTPStatus {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		try await req.store.deleteInventory(id: id)
		try await AuditService.write(
			req: req, entityType: "inventory", entityId: id, action: "archive")
		return .noContent
	}

	func bulk(req: Request) async throws -> BulkResult {
		let body = try req.content.decode(InventoryBulkRequest.self)
		var updated = 0
		var errors: [String] = []
		let now = Date()
		let userId = req.storage.get(UserKey.self)?.id
		for id in body.ids {
			guard var item = try await req.store.findInventory(by: id) else {
				errors.append("missing:\(id)")
				continue
			}
			switch body.action {
			case "adjustQuantity":
				guard let delta = body.quantityDelta else {
					errors.append("missingDelta:\(id)")
					continue
				}
				item.quantity = max(0, item.quantity + delta)
			case "setThreshold":
				guard let value = body.quantityDelta else {
					errors.append("missingValue:\(id)")
					continue
				}
				item.reorderThreshold = max(0, value)
			case "softDelete", "archive":
				item.deletedAt = now
			case "restore":
				item.deletedAt = nil
			default:
				errors.append("badAction:\(id)")
				continue
			}
			item.updatedAt = now
			item.updatedByUserId = userId
			_ = try await req.store.update(inventoryItem: item)
			updated += 1
		}
		try await AuditService.write(
			req: req, entityType: "inventory", entityId: "bulk", action: body.action,
			summary: "updated \(updated)")
		return BulkResult(updated: updated, errors: errors)
	}

	func exportCSV(req: Request) async throws -> CSVExportPayload {
		var filter = try InventoryListFilter.from(req: req)
		filter.limit = 5000
		filter.cursor = nil
		let page = try await req.store.pageInventory(filter: filter)
		var lines = ["id,sku,name,quantity,reorderThreshold,unit,tagIds"]
		for item in page.items {
			let tags = (item.tagIds ?? []).joined(separator: "|")
			let name = item.name.replacingOccurrences(of: ",", with: " ")
			lines.append(
				"\(item.id),\(item.sku),\(name),\(item.quantity),\(item.reorderThreshold),\(item.unit),\(tags)"
			)
		}
		return CSVExportPayload(csv: lines.joined(separator: "\n"))
	}

	func importCSV(req: Request) async throws -> CSVImportResult {
		let body = try req.content.decode(CSVImportRequest.self)
		let rows = body.csv.split(whereSeparator: \.isNewline).dropFirst()
		var upserted = 0
		var errors: [String] = []
		let userId = req.storage.get(UserKey.self)?.id
		let now = Date()
		for (idx, row) in rows.enumerated() {
			let cols = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
			guard cols.count >= 6 else {
				errors.append("row\(idx + 2):badColumns")
				continue
			}
			let id = cols[0].isEmpty ? ObjectId().hexString : cols[0]
			let sku = cols[1]
			let name = cols[2]
			guard let qty = Int(cols[3]), let threshold = Int(cols[4]) else {
				errors.append("row\(idx + 2):badNumbers")
				continue
			}
			let unit = cols[5]
			let tagIds = cols.count > 6 && !cols[6].isEmpty
				? cols[6].split(separator: "|").map(String.init) : nil
			let validated = try? await TagValidation.validateTagIds(store: req.store, tagIds: tagIds)
			if let existing = try await req.store.findInventory(by: id) {
				var item = existing
				item.name = name
				item.quantity = qty
				item.reorderThreshold = threshold
				item.unit = unit
				item.tagIds = validated
				item.updatedAt = now
				item.updatedByUserId = userId
				_ = try await req.store.update(inventoryItem: item)
			} else {
				let item = InventoryItem(
					id: id, sku: sku, name: name, quantity: qty, reorderThreshold: threshold,
					unit: unit, tagIds: validated, updatedAt: now, updatedByUserId: userId)
				_ = try await req.store.create(inventoryItem: item)
			}
			upserted += 1
		}
		return CSVImportResult(upserted: upserted, errors: errors)
	}
}

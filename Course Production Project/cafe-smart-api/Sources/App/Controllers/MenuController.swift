//
//  MenuController.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Vapor

actor MenuController {
	func list(req: Request) async throws -> PaginatedMenuItems {
		let filter = try MenuListFilter.from(req: req)
		let page = try await req.store.pageMenu(filter: filter)
		let version = try await req.application.catalogVersions.current()
		return PaginatedMenuItems(
			items: page.items, page: page.page, catalogVersion: version.version)
	}

	func catalogVersion(req: Request) async throws -> CatalogVersion {
		try await req.application.catalogVersions.current()
	}

	func create(req: Request) async throws -> MenuItem {
		let create = try req.content.decode(CreateMenuItemRequest.self)
		let name = create.name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { throw Abort(.badRequest, reason: "Name required") }
		guard create.priceCents >= 0 else { throw Abort(.badRequest, reason: "priceCents must be >= 0") }
		let userId = req.storage.get(UserKey.self)?.id
		let tagIds = try await TagValidation.validateTagIds(store: req.store, tagIds: create.tagIds)
		let imageURL = try Self.validatedManualImageURL(create.imageURL, app: req.application)
		let now = Date()
		let model = MenuItem(
			id: ObjectId().hexString,
			name: name,
			description: create.description,
			priceCents: create.priceCents,
			isAvailable: create.isAvailable,
			category: create.category,
			createdAt: now,
			subcategory: create.subcategory,
			sizeOptions: create.sizeOptions,
			prepSeconds: create.prepSeconds,
			prepStation: create.prepStation,
			allergens: create.allergens,
			tagIds: tagIds.isEmpty ? nil : tagIds,
			updatedAt: now,
			updatedByUserId: userId,
			loyaltyEarnEnabled: create.loyaltyEarnEnabled,
			loyaltyRedeemPoints: create.loyaltyRedeemPoints,
			imageURL: imageURL == "" ? nil : imageURL,
			imageMediaKey: nil)
		let created = try await req.store.create(menuItem: model)
		_ = try await req.application.catalogVersions.bump(reason: "create", req: req)
		try await AuditService.write(
			req: req, entityType: "menu", entityId: created.id, action: "create",
			summary: created.name)
		return created
	}

	func get(req: Request) async throws -> MenuItem {
		guard let idParam = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard let item = try await req.store.findMenuItem(by: idParam) else { throw Abort(.notFound) }
		return item
	}

	func update(req: Request) async throws -> MenuItem {
		guard let idParam = req.parameters.get("id") else { throw Abort(.badRequest) }
		let body = try req.content.decode(UpdateMenuItemRequest.self)
		guard var model = try await req.store.findMenuItem(by: idParam) else { throw Abort(.notFound) }
		if let name = body.name {
			let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { throw Abort(.badRequest, reason: "Name required") }
			model.name = trimmed
		}
		if let description = body.description { model.description = description }
		if let price = body.priceCents {
			guard price >= 0 else { throw Abort(.badRequest, reason: "priceCents must be >= 0") }
			model.priceCents = price
		}
		if let avail = body.isAvailable { model.isAvailable = avail }
		if let category = body.category { model.category = category }
		if let subcategory = body.subcategory { model.subcategory = subcategory }
		if let sizeOptions = body.sizeOptions { model.sizeOptions = sizeOptions }
		if let prepSeconds = body.prepSeconds { model.prepSeconds = prepSeconds }
		if let prepStation = body.prepStation { model.prepStation = prepStation }
		if let allergens = body.allergens { model.allergens = allergens }
		if body.tagIds != nil {
			model.tagIds = try await TagValidation.validateTagIds(
				store: req.store, tagIds: body.tagIds, existingTagIds: model.tagIds)
		}
		if let earn = body.loyaltyEarnEnabled { model.loyaltyEarnEnabled = earn }
		if let redeem = body.loyaltyRedeemPoints {
			guard redeem >= 0 else { throw Abort(.badRequest, reason: "loyaltyRedeemPoints must be >= 0") }
			model.loyaltyRedeemPoints = redeem
		}
		if let imageURL = body.imageURL {
			let validated = try Self.validatedManualImageURL(imageURL, app: req.application)
			if validated == "" {
				model.imageURL = nil
				model.imageMediaKey = nil
			} else if let validated {
				model.imageURL = validated
				// External/manual URL is not an owned media key.
				model.imageMediaKey = nil
			}
		}
		model.updatedAt = Date()
		model.updatedByUserId = req.storage.get(UserKey.self)?.id
		let updated = try await req.store.update(menuItem: model)
		_ = try await req.application.catalogVersions.bump(reason: "update", req: req)
		try await AuditService.write(
			req: req, entityType: "menu", entityId: updated.id, action: "update",
			summary: updated.name)
		return updated
	}

	func delete(req: Request) async throws -> HTTPStatus {
		guard let idParam = req.parameters.get("id") else { throw Abort(.badRequest) }
		try await req.store.deleteMenuItem(id: idParam)
		_ = try await req.application.catalogVersions.bump(reason: "archive", req: req)
		try await AuditService.write(
			req: req, entityType: "menu", entityId: idParam, action: "archive")
		return .noContent
	}

	func uploadImage(req: Request) async throws -> MenuItem {
		guard let idParam = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		guard var buffer = req.body.data, buffer.readableBytes > 0 else {
			throw Abort(.badRequest, reason: "Empty image body")
		}
		guard let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty else {
			throw Abort(.badRequest, reason: "Empty image body")
		}
		let contentType =
			(try? req.query.get(String.self, at: "contentType"))
			?? req.headers.contentType?.serialize()
			?? "application/octet-stream"
		return try await req.application.catalogMedia.uploadImage(
			menuItemId: idParam,
			bytes: bytes,
			contentType: contentType,
			adminId: user.id,
			req: req)
	}

	func clearImage(req: Request) async throws -> MenuItem {
		guard let idParam = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		return try await req.application.catalogMedia.clearImage(
			menuItemId: idParam, adminId: user.id, req: req)
	}

	func bulk(req: Request) async throws -> BulkResult {
		let body = try req.content.decode(MenuBulkRequest.self)
		var updated = 0
		var errors: [String] = []
		let now = Date()
		let userId = req.storage.get(UserKey.self)?.id
		for id in body.ids {
			guard var item = try await req.store.findMenuItem(by: id) else {
				errors.append("missing:\(id)")
				continue
			}
			switch body.action {
			case "setAvailable":
				guard let value = body.isAvailable else {
					errors.append("missingValue:\(id)")
					continue
				}
				item.isAvailable = value
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
			_ = try await req.store.update(menuItem: item)
			updated += 1
		}
		if updated > 0 {
			_ = try await req.application.catalogVersions.bump(reason: "bulk:\(body.action)", req: req)
		}
		try await AuditService.write(
			req: req, entityType: "menu", entityId: "bulk", action: body.action,
			summary: "updated \(updated)")
		return BulkResult(updated: updated, errors: errors)
	}

	func exportCSV(req: Request) async throws -> CSVExportPayload {
		var filter = try MenuListFilter.from(req: req)
		filter.limit = 5000
		filter.cursor = nil
		let page = try await req.store.pageMenu(filter: filter)
		var lines = ["id,name,priceCents,isAvailable,category,tagIds,imageURL,description,imageMediaKey"]
		for item in page.items {
			let tags = (item.tagIds ?? []).joined(separator: "|")
			let cat = item.category?.replacingOccurrences(of: ",", with: " ") ?? ""
			let name = item.name.replacingOccurrences(of: ",", with: " ")
			let image = (item.imageURL ?? "").replacingOccurrences(of: ",", with: "%2C")
			let desc = (item.description ?? "")
				.replacingOccurrences(of: "\"", with: "'")
				.replacingOccurrences(of: ",", with: " ")
			let key = item.imageMediaKey ?? ""
			lines.append(
				"\(item.id),\(name),\(item.priceCents),\(item.isAvailable),\(cat),\(tags),\(image),\(desc),\(key)"
			)
		}
		return CSVExportPayload(csv: lines.joined(separator: "\n"))
	}

	func importCSV(req: Request) async throws -> CSVImportResult {
		let body = try req.content.decode(CSVImportRequest.self)
		let rows = Self.parseCSVRows(body.csv)
		var upserted = 0
		var errors: [String] = []
		let userId = req.storage.get(UserKey.self)?.id
		let now = Date()
		for (idx, cols) in rows.enumerated() {
			guard cols.count >= 4 else {
				errors.append("row\(idx + 2):badColumns")
				continue
			}
			let id = cols[0].isEmpty ? ObjectId().hexString : cols[0]
			let name = cols[1]
			guard let price = Int(cols[2]) else {
				errors.append("row\(idx + 2):badPrice")
				continue
			}
			let available = cols[3].lowercased() == "true"
			let category = cols.count > 4 && !cols[4].isEmpty ? cols[4] : nil
			let tagIds = cols.count > 5 && !cols[5].isEmpty
				? cols[5].split(separator: "|").map(String.init) : nil
			let imageURLRaw = cols.count > 6 && !cols[6].isEmpty ? cols[6] : nil
			let description = cols.count > 7 && !cols[7].isEmpty ? cols[7] : nil
			let imageMediaKey = cols.count > 8 && !cols[8].isEmpty ? cols[8] : nil
			let imageURL: String?
			do {
				imageURL = try Self.validatedManualImageURL(imageURLRaw, app: req.application)
			} catch {
				errors.append("row\(idx + 2):badImageURL")
				continue
			}
			let validated = try? await TagValidation.validateTagIds(store: req.store, tagIds: tagIds)
			if let existing = try await req.store.findMenuItem(by: id) {
				var item = existing
				item.name = name
				item.priceCents = price
				item.isAvailable = available
				item.category = category
				item.tagIds = validated
				if let imageURL {
					item.imageURL = imageURL.isEmpty ? nil : imageURL
					if imageURL.isEmpty { item.imageMediaKey = nil }
				}
				if let imageMediaKey { item.imageMediaKey = imageMediaKey }
				if let description { item.description = description }
				item.updatedAt = now
				item.updatedByUserId = userId
				_ = try await req.store.update(menuItem: item)
			} else {
				let item = MenuItem(
					id: id, name: name, description: description, priceCents: price,
					isAvailable: available, category: category, createdAt: now, tagIds: validated,
					updatedAt: now, updatedByUserId: userId,
					imageURL: imageURL?.isEmpty == true ? nil : imageURL,
					imageMediaKey: imageMediaKey)
				_ = try await req.store.create(menuItem: item)
			}
			upserted += 1
		}
		if upserted > 0 {
			_ = try await req.application.catalogVersions.bump(reason: "import", req: req)
		}
		return CSVImportResult(upserted: upserted, errors: errors)
	}

	private static func validatedManualImageURL(_ raw: String?, app: Application) throws -> String? {
		do {
			return try MediaURLPolicy.validateManualImageURL(
				raw, allowedHosts: app.mediaAllowedHosts)
		} catch MediaURLPolicy.AbortReason.badImageURL {
			throw Abort(
				.badRequest,
				reason: "imageURL must be https and host allowlisted (or empty to clear)")
		}
	}

	/// RFC4180-ish CSV rows (supports quoted fields with commas). Skips header.
	private static func parseCSVRows(_ csv: String) -> [[String]] {
		var rows: [[String]] = []
		var field = ""
		var row: [String] = []
		var inQuotes = false
		var i = csv.startIndex
		while i < csv.endIndex {
			let ch = csv[i]
			if inQuotes {
				if ch == "\"" {
					let next = csv.index(after: i)
					if next < csv.endIndex, csv[next] == "\"" {
						field.append("\"")
						i = next
					} else {
						inQuotes = false
					}
				} else {
					field.append(ch)
				}
			} else if ch == "\"" {
				inQuotes = true
			} else if ch == "," {
				row.append(field)
				field = ""
			} else if ch == "\n" || ch == "\r" {
				if ch == "\r" {
					let next = csv.index(after: i)
					if next < csv.endIndex, csv[next] == "\n" { i = next }
				}
				row.append(field)
				field = ""
				if !(row.count == 1 && row[0].isEmpty) {
					rows.append(row)
				}
				row = []
			} else {
				field.append(ch)
			}
			i = csv.index(after: i)
		}
		if !field.isEmpty || !row.isEmpty {
			row.append(field)
			rows.append(row)
		}
		guard !rows.isEmpty else { return [] }
		return Array(rows.dropFirst())
	}
}

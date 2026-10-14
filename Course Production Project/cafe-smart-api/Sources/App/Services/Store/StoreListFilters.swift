//
//  StoreListFilters.swift
//  CafeSmartAPI
//

import Foundation

enum StoreListFilters {
	static func sortTimestamp(_ date: Date) -> String {
		String(format: "%.6f", date.timeIntervalSince1970)
	}

	static func sortName(_ name: String) -> String {
		name.lowercased()
	}

	static func sortInt(_ value: Int) -> String {
		String(format: "%010d", value)
	}

	static func matchesOrder(_ order: Order, filter: OrderListFilter) -> Bool {
		if let customerUserId = filter.customerUserId {
			guard order.customerUserId == customerUserId else { return false }
		}
		if !filter.statuses.isEmpty {
			guard filter.statuses.contains(order.status) else { return false }
		} else if let status = filter.status, order.status != status {
			return false
		}
		if let from = filter.from, order.createdAt < from { return false }
		if let to = filter.to, order.createdAt > to { return false }
		if let q = filter.q {
			let fields = [
				order.id,
				order.customerName ?? "",
				order.items.map { $0.name ?? "" }.joined(separator: " "),
			]
			guard ListSearch.matchesAny(q: q, fields: fields) else { return false }
		}
		return true
	}

	static func matchesMenu(_ item: MenuItem, filter: MenuListFilter, groupTagIds: Set<String>) -> Bool {
		if !filter.includeDeleted && item.deletedAt != nil { return false }
		if let category = filter.category, item.category != category { return false }
		if let isAvailable = filter.isAvailable, item.isAvailable != isAvailable { return false }
		if !filter.tagIds.isEmpty {
			let ids = Set(item.tagIds ?? [])
			guard !ids.isDisjoint(with: filter.tagIds) else { return false }
		}
		if !groupTagIds.isEmpty {
			let ids = Set(item.tagIds ?? [])
			guard !ids.isDisjoint(with: groupTagIds) else { return false }
		}
		if let q = filter.q {
			let fields = [item.name, item.description ?? "", item.category ?? ""]
			guard ListSearch.matchesAny(q: q, fields: fields) else { return false }
		}
		return true
	}

	static func matchesInventory(
		_ item: InventoryItem,
		filter: InventoryListFilter,
		groupTagIds: Set<String>
	) -> Bool {
		if !filter.includeDeleted && item.deletedAt != nil { return false }
		if filter.lowStock && item.quantity > item.reorderThreshold { return false }
		if let storage = filter.storage, item.storage != storage { return false }
		if !filter.tagIds.isEmpty {
			let ids = Set(item.tagIds ?? [])
			guard !ids.isDisjoint(with: filter.tagIds) else { return false }
		}
		if !groupTagIds.isEmpty {
			let ids = Set(item.tagIds ?? [])
			guard !ids.isDisjoint(with: groupTagIds) else { return false }
		}
		if let q = filter.q {
			let fields = [item.name, item.sku, item.supplier ?? ""]
			guard ListSearch.matchesAny(q: q, fields: fields) else { return false }
		}
		return true
	}

	static func matchesReservation(_ reservation: Reservation, filter: ReservationListFilter) -> Bool {
		if let customerUserId = filter.customerUserId {
			guard reservation.customerUserId == customerUserId else { return false }
		}
		if let status = filter.status, reservation.status != status { return false }
		if let from = filter.from, reservation.startTime < from { return false }
		if let to = filter.to, reservation.startTime > to { return false }
		if let q = filter.q {
			let fields = [
				reservation.name,
				reservation.phone ?? "",
				reservation.notes ?? "",
			]
			guard ListSearch.matchesAny(q: q, fields: fields) else { return false }
		}
		return true
	}

	static func matchesTagGroup(_ group: TagGroup, filter: TagGroupListFilter) -> Bool {
		if !filter.includeArchived && group.isArchived { return false }
		if let q = filter.q, !ListSearch.matches(group.name, q: q) { return false }
		return true
	}

	static func matchesTag(_ tag: Tag, filter: TagListFilter) -> Bool {
		if let groupId = filter.groupId, tag.groupId != groupId { return false }
		if !filter.includeArchived && tag.isArchived { return false }
		if let q = filter.q, !ListSearch.matches(tag.name, q: q) { return false }
		return true
	}

	static func matchesAudit(_ event: AuditEvent, filter: AuditListFilter) -> Bool {
		if let entityType = filter.entityType, event.entityType != entityType { return false }
		if let entityId = filter.entityId, event.entityId != entityId { return false }
		return true
	}

	static func matchesSupportTicket(_ ticket: SupportTicket, filter: SupportTicketListFilter) -> Bool {
		if let creatorUserId = filter.creatorUserId, ticket.creatorUserId != creatorUserId {
			return false
		}
		if filter.excludeHiddenByCreator, ticket.hiddenByCreatorAt != nil { return false }
		if filter.excludeSoftDeleted, ticket.deletedAt != nil { return false }
		if let status = filter.status, ticket.status != status { return false }
		if let q = filter.q {
			var fields = [ticket.message, ticket.creatorEmail, ticket.staffNote ?? ""]
			fields.append(contentsOf: ticket.relatedOrderIds ?? [])
			return ListSearch.matchesAny(q: q, fields: fields)
		}
		return true
	}

	static func groupTagIds(tags: [Tag], groupId: String?) -> Set<String> {
		guard let groupId else { return [] }
		return Set(tags.filter { $0.groupId == groupId }.map(\.id))
	}
}

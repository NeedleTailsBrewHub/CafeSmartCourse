//
//  ReservationController.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Foundation
import Vapor

actor ReservationController {
	func list(req: Request) async throws -> PaginatedReservations {
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		let merchantFloor = RoleGate.isMerchantFloor(
			for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)
		// `mine=true` / `scope=mine` always returns the caller's bookings — even for staff —
		// so guest "My reservations" never sees the full café floor list.
		let forceMine = Self.requestsMineScope(req)
		let customerScope: String? = (forceMine || !merchantFloor) ? user.id : nil
		let filter = try ReservationListFilter.from(req: req, customerUserId: customerScope)
		let page = try await req.store.pageReservations(filter: filter)
		return PaginatedReservations(items: page.items, page: page.page)
	}

	/// Day slot grid: only times that fit party size, tables, hours, and seating cap.
	func availability(req: Request) async throws -> ReservationAvailabilityResponse {
		guard req.storage.get(UserKey.self) != nil else { throw Abort(.unauthorized) }
		guard let dateRaw = req.query[String.self, at: "date"], !dateRaw.isEmpty else {
			throw Abort(.badRequest, reason: "date=YYYY-MM-DD is required")
		}
		let partySize = req.query[Int.self, at: "partySize"] ?? 2
		guard partySize > 0, partySize <= 40 else {
			throw Abort(.badRequest, reason: "partySize must be between 1 and 40")
		}

		// Parallelize independent store reads — biggest win after scoped reservation query.
		async let configTask = req.store.getBusinessConfig()
		async let tablesTask = req.store.listTables()
		async let areasTask = req.store.listSeatingAreas()
		let config = try await configTask
		let tables = try await tablesTask
		let areas = try await areasTask

		let calendar = ReservationAvailability.calendar(for: config?.timezone ?? TimeZone.current.identifier)
		guard let day = ReservationAvailability.parseDay(dateRaw, calendar: calendar) else {
			throw Abort(.badRequest, reason: "Invalid date")
		}
		let dayStart = calendar.startOfDay(for: day)
		guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
			throw Abort(.badRequest, reason: "Invalid date")
		}

		// One indexed day query (limit covers a busy café floor). No full-collection scan,
		// no DemandInference / listOrders — those were dominating latency.
		let page = try await req.store.pageReservations(
			filter: ReservationListFilter(
				limit: 500,
				from: dayStart,
				to: dayEnd.addingTimeInterval(-1)))
		var reservations = page.items
		if page.page.hasMore, let next = page.page.nextCursor {
			let more = try await req.store.pageReservations(
				filter: ReservationListFilter(
					limit: 500,
					cursor: try ListCursor.decode(next),
					from: dayStart,
					to: dayEnd.addingTimeInterval(-1)))
			reservations.append(contentsOf: more.items)
		}

		return ReservationAvailability.slots(
			dateRaw: dateRaw,
			partySize: partySize,
			config: config,
			tables: tables,
			areas: areas,
			reservations: reservations)
	}

	func create(req: Request) async throws -> Reservation {
		let body = try req.content.decode(CreateReservationRequest.self)
		guard body.partySize > 0 else { throw Abort(.badRequest) }
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		let merchantFloor = RoleGate.isMerchantFloor(
			for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)

		async let configTask = req.store.getBusinessConfig()
		async let tablesTask = req.store.listTables()
		async let areasTask = req.store.listSeatingAreas()
		let config = try await configTask
		let tables = try await tablesTask
		let areas = try await areasTask

		let calendar = ReservationAvailability.calendar(for: config?.timezone ?? TimeZone.current.identifier)
		let dayStart = calendar.startOfDay(for: body.startTime)
		guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
			throw Abort(.badRequest, reason: "Invalid startTime")
		}
		let existing = try await req.store.pageReservations(
			filter: ReservationListFilter(limit: 500, from: dayStart, to: dayEnd.addingTimeInterval(-1)))
		var reservations = existing.items
		if existing.page.hasMore, let nextCursor = existing.page.nextCursor {
			let more = try await req.store.pageReservations(
				filter: ReservationListFilter(
					limit: 500,
					cursor: try ListCursor.decode(nextCursor),
					from: dayStart,
					to: dayEnd.addingTimeInterval(-1)))
			reservations.append(contentsOf: more.items)
		}

		// Guests may request a specific free table/area; server re-validates against live slot.
		let preferredTableId = body.tableId
		let preferredAreaId = body.areaId
		guard let assignment = ReservationAvailability.assignment(
			startTime: body.startTime,
			partySize: body.partySize,
			config: config,
			tables: tables,
			areas: areas,
			reservations: reservations,
			preferredTableId: preferredTableId,
			preferredAreaId: preferredAreaId)
		else {
			throw Abort(
				.conflict,
				reason: "That time is no longer available for a party of \(body.partySize). Pick another slot.")
		}

		// If a specific table was requested, ensure assignment honored it (still free).
		if let preferredTableId, assignment.tableId != preferredTableId {
			throw Abort(
				.conflict,
				reason: "That table is no longer available. Pick another table or time.")
		}

		// Guests cannot set merchant-only fields.
		let status: ReservationStatus = merchantFloor ? (body.status ?? .active) : .active
		let internalNotes: String? = merchantFloor ? body.internalNotes : nil
		let model = Reservation(
			id: ObjectId().hexString,
			name: body.name,
			partySize: body.partySize,
			startTime: body.startTime,
			phone: body.phone,
			notes: body.notes,
			durationMinutes: body.durationMinutes ?? assignment.turnMinutes,
			seatsOccupied: body.seatsOccupied ?? assignment.seatsOccupied,
			areaId: assignment.areaId,
			tableId: assignment.tableId,
			status: status,
			specialOccasion: body.specialOccasion,
			internalNotes: internalNotes,
			orderId: merchantFloor ? body.orderId : nil,
			customerUserId: user.id)
		let created = try await req.store.create(reservation: model)
		await req.application.realtime.publish(.reservation(.created(created)), to: .merchant)
		await req.application.realtime.publish(
			.reservation(.created(created)), to: .customer, userId: created.customerUserId)
		return created
	}

	private static func requestsMineScope(_ req: Request) -> Bool {
		let mine = req.query[String.self, at: "mine"]?.lowercased()
		let scope = req.query[String.self, at: "scope"]?.lowercased()
		return mine == "1" || mine == "true" || scope == "mine"
	}

	func get(req: Request) async throws -> Reservation {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard let reservation = try await req.store.findReservation(by: id) else {
			throw Abort(.notFound)
		}
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		let merchantFloor = RoleGate.isMerchantFloor(
			for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)
		if !merchantFloor && reservation.customerUserId != user.id { throw Abort(.forbidden) }
		return reservation
	}

	func cancel(req: Request) async throws -> Reservation {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard var reservation = try await req.store.findReservation(by: id) else {
			throw Abort(.notFound)
		}
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		let merchantFloor = RoleGate.isMerchantFloor(
			for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)
		if !merchantFloor {
			guard reservation.customerUserId == user.id else { throw Abort(.forbidden) }
			guard reservation.status == nil || reservation.status == .active else {
				throw Abort(.forbidden, reason: "Only active reservations can be canceled")
			}
		}
		reservation.status = .canceled
		let updated = try await req.store.update(reservation: reservation)
		await req.application.realtime.publish(.reservation(.updated(updated)), to: .merchant)
		await req.application.realtime.publish(
			.reservation(.updated(updated)), to: .customer, userId: updated.customerUserId)
		return updated
	}

	func delete(req: Request) async throws -> HTTPStatus {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		if let existing = try await req.store.findReservation(by: id) {
			try await req.store.deleteReservation(id: id)
			await req.application.realtime.publish(.reservation(.deleted(existing)), to: .merchant)
			await req.application.realtime.publish(
				.reservation(.deleted(existing)), to: .customer, userId: existing.customerUserId)
		} else {
			try await req.store.deleteReservation(id: id)
		}
		return .noContent
	}
}

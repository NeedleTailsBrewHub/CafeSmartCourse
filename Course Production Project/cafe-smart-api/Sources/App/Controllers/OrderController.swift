//
//  OrderController.swift
//  CafeSmartAPI
//

import Vapor

actor OrderController {
	func list(req: Request) async throws -> PaginatedOrders {
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		let requestIsAdmin = req.storage.get(IsAdminKey.self) == true
		let merchantFloor = RoleGate.isMerchantFloor(for: user, requestIsAdmin: requestIsAdmin)
		let mine = req.query[String.self, at: "mine"]?.lowercased()
		let scope = req.query[String.self, at: "scope"]?.lowercased()
		let forceMine = mine == "1" || mine == "true" || scope == "mine"
		let customerScope: String? = (forceMine || !merchantFloor) ? user.id : nil
		let filter = try OrderListFilter.from(req: req, customerUserId: customerScope)
		let page = try await req.store.pageOrders(filter: filter)
		return PaginatedOrders(items: page.items, page: page.page)
	}

	func create(req: Request) async throws -> Order {
		let create = try req.content.decode(CreateOrderRequest.self)
		if create.paymentMode == .prepaid {
			throw Abort(
				.badRequest,
				reason: "Prepaid orders must use POST /api/auth/checkout/confirm")
		}
		let config = try await req.store.getBusinessConfig()
		guard PaymentsPolicy.payAtPickupEnabled(config: config) else {
			throw Abort(
				.forbidden,
				reason: "Pay at pickup is disabled; use in-app Pay now")
		}
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }

		let draft = try await OrderCheckoutService.quote(
			req: req,
			userId: user.id,
			items: create.items,
			useLoyaltyPoints: create.useLoyaltyPoints,
			customerName: create.customerName,
			pickupTime: create.pickupTime,
			channel: create.channel,
			serviceType: create.serviceType,
			tableId: create.tableId,
			guests: create.guests,
			reservationId: create.reservationId)

		let paymentStatus: OrderPaymentStatus =
			draft.quote.totalCents == 0 ? .waived : .unpaid

		return try await OrderCheckoutService.placeOrder(
			req: req,
			userId: user.id,
			draft: draft,
			paymentStatus: paymentStatus,
			paidAt: paymentStatus == .waived ? Date() : nil)
	}

	func get(req: Request) async throws -> Order {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard let order = try await req.store.findOrder(by: id) else { throw Abort(.notFound) }
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		let merchantFloor = RoleGate.isMerchantFloor(
			for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)
		if !merchantFloor && order.customerUserId != user.id { throw Abort(.forbidden) }
		return order
	}

	func updateStatus(req: Request) async throws -> Order {
		let body = try req.content.decode(UpdateOrderStatusRequest.self)
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		guard var order = try await req.store.findOrder(by: id) else { throw Abort(.notFound) }
		guard let user = req.storage.get(UserKey.self) else { throw Abort(.unauthorized) }
		let merchantFloor = RoleGate.isMerchantFloor(
			for: user, requestIsAdmin: req.storage.get(IsAdminKey.self) == true)

		let previous = order.status
		if merchantFloor {
			guard OrderStatusFSM.canAdminTransition(from: previous, to: body.status) else {
				throw Abort(
					.conflict,
					reason: "Illegal status transition \(previous.rawValue) → \(body.status.rawValue)")
			}
			order.status = body.status
		} else {
			guard order.customerUserId == user.id else { throw Abort(.forbidden) }
			guard previous == .pending, body.status == .canceled else {
				throw Abort(.forbidden, reason: "Customers can only cancel pending orders")
			}
			order.status = .canceled
		}

		if order.status == .canceled, previous != .canceled,
			OrderStatusFSM.isEarlyCancelStage(previous)
		{
			try? await OrderInventoryService.restore(req: req, items: order.items)
			if order.paymentStatus == .paid, let piId = order.stripePaymentIntentId,
				!piId.isEmpty
			{
				do {
					try await req.application.stripeClient.refundPaymentIntent(id: piId)
					order.paymentStatus = .unpaid
					order.paidAt = nil
					req.logger.info(
						"Refunded prepaid order on cancel",
						metadata: [
							"orderId": .string(order.id),
							"paymentIntentId": .string(piId),
						])
				} catch {
					req.logger.error(
						"CRITICAL: canceled paid order but Stripe refund failed",
						metadata: [
							"orderId": .string(order.id),
							"paymentIntentId": .string(piId),
							"error": .string("\(error)"),
						])
				}
			}
		}

		// Pay-at-pickup: completing the ticket means cash/card was collected at the counter.
		if order.status == .completed, previous != .completed,
			order.paymentStatus == nil || order.paymentStatus == .unpaid
		{
			order.paymentStatus = .paid
			order.paidAt = Date()
		}

		let updated = try await req.store.update(order: order)
		try? await AuditService.write(
			req: req, entityType: "order", entityId: updated.id, action: "status",
			summary: "\(previous.rawValue)→\(updated.status.rawValue)")
		await req.application.realtime.publish(.order(.updated(updated)), to: .merchant)
		await req.application.realtime.publish(
			.order(.updated(updated)), to: .customer, userId: updated.customerUserId)
		return updated
	}

	func delete(req: Request) async throws -> HTTPStatus {
		guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
		try await req.store.deleteOrder(id: id)
		return .noContent
	}
}

//
//  OrderController.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/28/25.
//
import Vapor
import MongoKitten

actor OrderController {
    
    func create(req: Request) async throws -> Order {
        let create = try req.content.decode(OrderCreateRequest.self)
        
        guard !create.items.isEmpty else {
            throw Abort(.badRequest, reason: "Order must contain at least one item")
        }
        
        let order = Order(
            id: ObjectId().hexString,
            status: .pending,
            customerName: create.customerName,
            items: create.items,
            pickupTime: create.pickupTime,
            createdAt: Date())
        
        let created = try await req.store.create(order: order)
        
        return created
        
    }
    
    func list(req: Request) async throws -> OrdersWrapper {
        let items = try await req.store.listOrders()
        return OrdersWrapper(items: items)
    }
    
    func get(req: Request) async throws -> Order {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        guard let order = try await req.store.findOrder(by: id) else {
            throw Abort(.notFound)
        }
        return order
    }
    
    func updateStatus(req: Request) async throws -> Order {
        let body = try req.content.decode(OrderStatusUpdateRequest.self)
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        guard var order = try await req.store.findOrder(by: id) else {
            throw Abort(.notFound)
        }
        order.status = body.status
        let updated = try await req.store.update(order: order)
        if body.status == .completed {
            
            //TODO:
            
        } else if body.status == .canceled {
            //        TODO:
        }
        return updated
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteOrder(id: id)
        return .ok
    }
    
}

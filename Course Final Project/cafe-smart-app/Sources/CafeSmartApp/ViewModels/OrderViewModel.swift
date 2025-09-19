//
//  OrderViewModel.swift
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

import Observation
import SkipFuse
import BSON
import Foundation

enum Constants {
#if DEBUG
    static let httpHost: String = "http://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#else
    static let httpHost: String = "https://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#endif
}

@MainActor
@Observable
final class OrderViewModel {
    
    // MARK: - State
    var orders: [Order] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - API
    func fetchOrders() async throws {
        isLoading = true
        defer { isLoading = false }
        let response: Response<OrdersWrapper> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/orders",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let data = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        orders = data.items
    }

    func createOrder(_ requestModel: CreateOrderRequest) async throws -> Order {
        let body = try BSONEncoder().encode(requestModel).makeData()
        let response: Response<Order> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/auth/orders",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let order = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        print("CREATE ORDER: \(order)")
        orders.append(order)
        return order
    }

    func fetchOrder(id: String) async throws -> Order {
        let response: Response<Order> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/orders/\(id)",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let order = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        return order
    }

    func updateOrderStatus(id: String, status: OrderStatus) async throws -> Order {
        let body = try BSONEncoder().encode(UpdateOrderStatusRequest(status: status)).makeData()
        let response: Response<Order> = try await URLSession.shared.request(
            method: .patch,
            httpHost: Constants.httpHost,
            url: "api/auth/orders/\(id)/status",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let order = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        if let idx = orders.firstIndex(where: { $0.id == id }) {
            orders[idx] = order
        }
        return order
    }

    func deleteOrder(id: String) async throws {
        let response: Response<Data> = try await URLSession.shared.request(
            method: .delete,
            httpHost: Constants.httpHost,
            url: "api/auth/orders/\(id)",
            token: nil,
            body: Data()
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode) else {
            throw Errors.failedRequest(http.statusCode)
        }
        orders.removeAll { $0.id == id }
    }
}

// moved to Models/CollectionModels.swift

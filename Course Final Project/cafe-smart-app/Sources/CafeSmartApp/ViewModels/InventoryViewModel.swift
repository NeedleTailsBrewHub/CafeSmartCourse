//
//  InventoryViewModel.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/10/25.
//
import SkipFuse
import Foundation
import Observation
import BSON

enum Constants {
#if DEBUG
    static let httpHost: String = "http://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#else
    static let httpHost: String = "https://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#endif
}

enum Errors: Error {
    case failedRequest(Int), invalidData
}

@MainActor
@Observable
final class InventoryViewModel {
    
    var items: [InventoryItem] = []
    var isLoading: Bool = false
    var errorMessage: String?
    
    
    // MARK: - API
    func fetchInventory() async throws {
        logger.info("Will Fetched inventory")
        isLoading = true
        defer { isLoading = false }
        let response: Response<InventoryItemsWrapper> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/inventory",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let data = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        items = data.items
        logger.info("Fetched inventory \(self.items)")
    }

    func fetchInventoryItem(id: String) async throws -> InventoryItem {
        let response: Response<InventoryItem> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/inventory/\(id)",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let item = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        return item
    }

    func createInventoryItem(_ requestModel: CreateInventoryItemRequest) async throws -> InventoryItem {
        let body = try BSONEncoder().encode(requestModel).makeData()
        let response: Response<InventoryItem> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/auth/inventory",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let item = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        items.append(item)
        return item
    }

    func updateInventoryItem(id: String, with requestModel: UpdateInventoryItemRequest) async throws -> InventoryItem {
        let body = try BSONEncoder().encode(requestModel).makeData()
        let response: Response<InventoryItem> = try await URLSession.shared.request(
            method: .put,
            httpHost: Constants.httpHost,
            url: "api/auth/inventory/\(id)",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let item = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = item
        }
        return item
    }

    func deleteInventoryItem(id: String) async throws {
        let response: Response<Data> = try await URLSession.shared.request(
            method: .delete,
            httpHost: Constants.httpHost,
            url: "api/auth/inventory/\(id)",
            token: nil,
            body: Data()
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode) else {
            throw Errors.failedRequest(http.statusCode)
        }
        items.removeAll { $0.id == id }
    }
    
    
}


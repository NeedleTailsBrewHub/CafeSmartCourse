//
//  MenuViewModel.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/10/25.
//

import Observation
import SkipFuseUI
import BSON
import JWTKit
#if SKIP
import SkipFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
final class MenuViewModel {
    // MARK: - State
    var items: [MenuItem] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - API
    func fetchMenu() async throws {
        isLoading = true
        defer { isLoading = false }
        let response: Response<MenuItemsWrapper> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/menu",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let data = response.data else {
            throw Errors.failedRequest((response.urlResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }
        items = data.items
    }

    func fetchMenuItem(id: String) async throws -> MenuItem {
        let response: Response<MenuItem> = try await URLSession.shared.request(
            method: .get,
            httpHost: Constants.httpHost,
            url: "api/auth/menu/\(id)",
            token: nil,
            body: nil
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let item = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        return item
    }

    func createMenuItem(_ requestModel: CreateMenuItemRequest) async throws -> MenuItem {
        let body = try BSONEncoder().encode(requestModel).makeData()
        let response: Response<MenuItem> = try await URLSession.shared.request(
            method: .post,
            httpHost: Constants.httpHost,
            url: "api/auth/menu",
            token: nil,
            body: body
        )
        let http = response.urlResponse as! HTTPURLResponse
        guard (200...299).contains(http.statusCode), let item = response.data else {
            throw Errors.failedRequest(http.statusCode)
        }
        // Update local cache
        items.append(item)
        return item
    }

    func updateMenuItem(id: String, with requestModel: UpdateMenuItemRequest) async throws -> MenuItem {
        let body = try BSONEncoder().encode(requestModel).makeData()
        let response: Response<MenuItem> = try await URLSession.shared.request(
            method: .put,
            httpHost: Constants.httpHost,
            url: "api/auth/menu/\(id)",
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

    func deleteMenuItem(id: String) async throws {
        let response: Response<Data> = try await URLSession.shared.request(
            method: .delete,
            httpHost: Constants.httpHost,
            url: "api/auth/menu/\(id)",
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
// moved to Models/CollectionModels.swift

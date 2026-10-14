//
//  CatalogVersionService.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

actor CatalogVersionService {
    private let app: Application

    init(app: Application) {
        self.app = app
    }

    func current() async throws -> CatalogVersion {
        try await app.mongoStore.getCatalogMeta().asVersion
    }

    @discardableResult
    func bump(reason: String, req: Request? = nil) async throws -> CatalogVersion {
        let meta = try await app.mongoStore.bumpCatalogVersion()
        let version = meta.asVersion
        app.logger.info("catalogVersion bumped to \(version.version) reason=\(reason)")
        await app.realtime.publish(.catalogVersion(version), to: .customer)
        await app.realtime.publish(.catalogVersion(version), to: .merchant)
        return version
    }
}

extension Application {
    private struct CatalogVersionServiceKey: StorageKey {
        typealias Value = CatalogVersionService
    }

    var catalogVersions: CatalogVersionService {
        get {
            if let existing = storage[CatalogVersionServiceKey.self] {
                return existing
            }
            let service = CatalogVersionService(app: self)
            storage[CatalogVersionServiceKey.self] = service
            return service
        }
        set { storage[CatalogVersionServiceKey.self] = newValue }
    }
}

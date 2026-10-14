//
//  CatalogMediaService.swift
//  CafeSmartAPI
//

import Foundation
import Vapor

actor CatalogMediaService {
    private let app: Application

    init(app: Application) {
        self.app = app
    }

    func uploadImage(
        menuItemId: String,
        bytes: [UInt8],
        contentType: String,
        adminId: String,
        req: Request
    ) async throws -> MenuItem {
        do {
            try await app.mediaRateLimiter.check(adminId: adminId)
        } catch MediaError.rateLimited {
            throw Abort(.tooManyRequests, reason: "Upload rate limit exceeded")
        }

        let maxBytes = Int(Environment.get("MEDIA_MAX_UPLOAD_BYTES") ?? "")
            ?? MediaImageValidator.defaultMaxBytes
        let maxPixels = Int(Environment.get("MEDIA_MAX_PIXELS") ?? "")
            ?? MediaImageValidator.defaultMaxPixels

        let validated: MediaImageValidator.Result
        do {
            validated = try MediaImageValidator.validate(
                bytes: bytes,
                declaredContentType: contentType,
                maxBytes: maxBytes,
                maxPixels: maxPixels)
        } catch MediaError.emptyBody {
            throw Abort(.badRequest, reason: "Empty image body")
        } catch MediaError.payloadTooLarge {
            throw Abort(.payloadTooLarge, reason: "Image exceeds size limit")
        } catch MediaError.unsupportedContentType {
            throw Abort(.badRequest, reason: "Unsupported content type")
        } catch MediaError.magicMismatch {
            throw Abort(.badRequest, reason: "Image magic bytes do not match content type")
        } catch MediaError.pixelLimitExceeded {
            throw Abort(.badRequest, reason: "Image dimensions exceed limit")
        }

        guard var item = try await app.mongoStore.findMenuItem(by: menuItemId) else {
            throw Abort(.notFound, reason: "Menu item not found")
        }
        let previousKey = item.imageMediaKey
        let key: String
        do {
            key = try MediaKey.make(menuItemId: menuItemId, ext: validated.ext)
        } catch MediaError.invalidMenuItemId {
            throw Abort(.badRequest, reason: "Invalid menu item id")
        } catch MediaError.unsupportedContentType {
            throw Abort(.badRequest, reason: "Unsupported content type")
        }

        let put: MediaPutResult
        do {
            put = try await app.mediaStorage.put(
                key: key, contentType: validated.contentType, bytes: bytes)
        } catch {
            throw Abort(
                .badGateway,
                reason: "Media storage put failed: \(error.localizedDescription)")
        }

        item.imageURL = put.publicURL
        item.imageMediaKey = put.key
        item.updatedAt = Date()
        item.updatedByUserId = adminId

        do {
            let updated = try await app.mongoStore.update(menuItem: item)
            if let previousKey, previousKey != put.key {
                do {
                    try await app.mediaStorage.delete(key: previousKey)
                } catch {
                    app.logger.warning(
                        "Failed to delete previous media key \(previousKey): \(error)")
                }
            }
            _ = try await app.catalogVersions.bump(reason: "image_upload", req: req)
            try await AuditService.write(
                req: req, entityType: "menu", entityId: updated.id, action: "image_upload",
                summary: "\(put.key) \(put.byteCount)b \(put.contentType)")
            app.logger.info(
                "menu image uploaded id=\(updated.id) key=\(put.key) bytes=\(put.byteCount)")
            return updated
        } catch {
            do {
                try await app.mediaStorage.delete(key: put.key)
            } catch {
                app.logger.error("Orphan cleanup failed for \(put.key): \(error)")
            }
            throw Abort(.internalServerError, reason: "Failed to persist menu image")
        }
    }

    func clearImage(menuItemId: String, adminId: String, req: Request) async throws -> MenuItem {
        guard var item = try await app.mongoStore.findMenuItem(by: menuItemId) else {
            throw Abort(.notFound, reason: "Menu item not found")
        }
        let previousKey = item.imageMediaKey
        item.imageURL = nil
        item.imageMediaKey = nil
        item.updatedAt = Date()
        item.updatedByUserId = adminId
        let updated = try await app.mongoStore.update(menuItem: item)
        if let previousKey {
            do {
                try await app.mediaStorage.delete(key: previousKey)
            } catch {
                app.logger.warning("Failed to delete media key \(previousKey): \(error)")
            }
        }
        _ = try await app.catalogVersions.bump(reason: "image_clear", req: req)
        try await AuditService.write(
            req: req, entityType: "menu", entityId: updated.id, action: "image_clear",
            summary: previousKey ?? "none")
        return updated
    }
}

extension Application {
    private struct MediaStorageKey: StorageKey {
        typealias Value = any MediaStorage
    }
    private struct CatalogMediaServiceKey: StorageKey {
        typealias Value = CatalogMediaService
    }
    private struct MediaRateLimiterKey: StorageKey {
        typealias Value = MediaUploadRateLimiter
    }
    private struct MediaAllowedHostsKey: StorageKey {
        typealias Value = Set<String>
    }

    var mediaStorage: any MediaStorage {
        get {
            storage[MediaStorageKey.self] ?? LocalMediaStorage(
                rootDirectory: URL(fileURLWithPath: directory.publicDirectory)
                    .appendingPathComponent("menu-images"))
        }
        set { storage[MediaStorageKey.self] = newValue }
    }

    /// True when a test or host injected storage before `configure`.
    var hasInjectedMediaStorage: Bool {
        storage[MediaStorageKey.self] != nil
    }

    var catalogMedia: CatalogMediaService {
        get {
            if let existing = storage[CatalogMediaServiceKey.self] { return existing }
            let service = CatalogMediaService(app: self)
            storage[CatalogMediaServiceKey.self] = service
            return service
        }
        set { storage[CatalogMediaServiceKey.self] = newValue }
    }

    var mediaRateLimiter: MediaUploadRateLimiter {
        get {
            if let existing = storage[MediaRateLimiterKey.self] { return existing }
            let limiter = MediaUploadRateLimiter()
            storage[MediaRateLimiterKey.self] = limiter
            return limiter
        }
        set { storage[MediaRateLimiterKey.self] = newValue }
    }

    var mediaAllowedHosts: Set<String> {
        get { storage[MediaAllowedHostsKey.self] ?? [] }
        set { storage[MediaAllowedHostsKey.self] = newValue }
    }
}

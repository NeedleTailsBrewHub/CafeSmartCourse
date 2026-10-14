//
//  FakeMediaStorage.swift
//  CafeSmartAPI
//

import Foundation

public actor FakeMediaStorage: MediaStorage {
    public struct PutRecord: Sendable, Equatable {
        public var key: String
        public var contentType: String
        public var byteCount: Int
    }

    public private(set) var puts: [PutRecord] = []
    public private(set) var deletes: [String] = []
    public var publicBaseURL: String
    public var failNextPut: Bool = false
    public var failNextDelete: Bool = false

    public init(publicBaseURL: String = "https://media.test") {
        self.publicBaseURL = publicBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func put(key: String, contentType: String, bytes: [UInt8]) async throws -> MediaPutResult {
        if failNextPut {
            failNextPut = false
            throw MediaError.storageFailed("fake put failure")
        }
        puts.append(PutRecord(key: key, contentType: contentType, byteCount: bytes.count))
        return MediaPutResult(
            key: key,
            publicURL: "\(publicBaseURL)/\(key)",
            contentType: contentType,
            byteCount: bytes.count)
    }

    public func delete(key: String) async throws {
        if failNextDelete {
            failNextDelete = false
            throw MediaError.storageFailed("fake delete failure")
        }
        deletes.append(key)
    }

    public func reset() {
        puts = []
        deletes = []
        failNextPut = false
        failNextDelete = false
    }
}

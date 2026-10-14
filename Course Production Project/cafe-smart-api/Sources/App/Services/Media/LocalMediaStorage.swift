//
//  LocalMediaStorage.swift
//  CafeSmartAPI
//

import Foundation

public actor LocalMediaStorage: MediaStorage {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func put(key: String, contentType: String, bytes: [UInt8]) async throws -> MediaPutResult {
        let fileURL = rootDirectory.appendingPathComponent(key)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: fileURL, options: .atomic)
        return MediaPutResult(
            key: key,
            publicURL: "/menu-images/\(key)",
            contentType: contentType,
            byteCount: bytes.count)
    }

    public func delete(key: String) async throws {
        let fileURL = rootDirectory.appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

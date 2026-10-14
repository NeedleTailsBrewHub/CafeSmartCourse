//
//  MediaStorage.swift
//  CafeSmartAPI
//

import Foundation

public struct MediaPutResult: Sendable, Equatable {
    public let key: String
    public let publicURL: String
    public let contentType: String
    public let byteCount: Int

    public init(key: String, publicURL: String, contentType: String, byteCount: Int) {
        self.key = key
        self.publicURL = publicURL
        self.contentType = contentType
        self.byteCount = byteCount
    }
}

public protocol MediaStorage: Sendable {
    func put(key: String, contentType: String, bytes: [UInt8]) async throws -> MediaPutResult
    func delete(key: String) async throws
}

public struct MediaHTTPRequest: Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: [UInt8]?

    public init(method: String, url: String, headers: [String: String] = [:], body: [UInt8]? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct MediaHTTPResponse: Sendable {
    public var status: Int
    public var body: [UInt8]

    public init(status: Int, body: [UInt8] = []) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPClientPerforming: Sendable {
    func execute(_ request: MediaHTTPRequest) async throws -> MediaHTTPResponse
}

public enum MediaKey {
    public static func make(menuItemId: String, ext: String) throws -> String {
        let id = menuItemId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              !id.contains(".."),
              !id.contains("/"),
              !id.contains("\\"),
              !id.contains("\0")
        else {
            throw MediaError.invalidMenuItemId
        }
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard ["jpg", "jpeg", "png", "webp"].contains(cleanExt) else {
            throw MediaError.unsupportedContentType(cleanExt)
        }
        let normalized = cleanExt == "jpeg" ? "jpg" : cleanExt
        return "menu/\(id)/\(UUID().uuidString.lowercased()).\(normalized)"
    }
}

public enum MediaError: Error, Sendable, Equatable {
    case invalidMenuItemId
    case emptyBody
    case payloadTooLarge(max: Int)
    case unsupportedContentType(String)
    case magicMismatch
    case pixelLimitExceeded
    case storageFailed(String)
    case rateLimited
}

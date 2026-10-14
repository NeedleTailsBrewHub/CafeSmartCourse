//
//  RequestIDMiddleware.swift
//  CafeSmartAPI
//

@preconcurrency import BSON
import Vapor

struct RequestIDKey: StorageKey {
    typealias Value = String
}

struct RequestIDMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let incoming = request.headers.first(name: "X-Request-ID")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestId =
            (incoming?.isEmpty == false ? incoming! : ObjectId().hexString)
        request.storage[RequestIDKey.self] = requestId
        request.logger[metadataKey: "request-id"] = .string(requestId)

        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Request-ID", value: requestId)
        return response
    }
}

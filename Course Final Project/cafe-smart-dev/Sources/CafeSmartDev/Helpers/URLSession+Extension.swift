//
//  URLSession+Extension.swift
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

#if SKIP
import SkipFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BinaryCodable
import SkipKeychain
@_spi(PostQuantum) import JWTKit

enum RequestType: String {
    case post = "POST"
    case get = "GET"
    case delete = "DELETE"
    case put = "PUT"
    case patch = "PATCH"
}

struct Response<T: Codable & Sendable>: Sendable {
    let data: T?
    let urlResponse: URLResponse
}

struct TokenResponse: Codable {
   let token: String
   let refreshToken: String?
   let expiresAt: Date
   let user: UserPublic
}

extension URLSession {
    enum Errors: Error {
        case httpBodyIsEmpty, responseError(String, String)
    }

    // MARK: - Token Storage Helpers
    actor AuthTokenStore {
        static let shared = AuthTokenStore()
        private static let accessKey = "com.example.app.access-token"
        private static let refreshKey = "com.example.app.refresh-token"

        /// In-memory cache so background actors (e.g. AIService train) don't depend on
        /// Keychain access from a non-main thread, which can fail silently with `try?`.
        private var cachedAccessToken: String?
        private var cachedRefreshToken: String?

        func getAccessToken() async -> String? {
            if let cachedAccessToken, !cachedAccessToken.isEmpty { return cachedAccessToken }
            let token = await MainActor.run {
                try? Keychain.shared.string(forKey: Self.accessKey)
            }
            cachedAccessToken = token
            return token
        }

        func getRefreshToken() async -> String? {
            if let cachedRefreshToken, !cachedRefreshToken.isEmpty { return cachedRefreshToken }
            let token = await MainActor.run {
                try? Keychain.shared.string(forKey: Self.refreshKey)
            }
            cachedRefreshToken = token
            return token
        }

        func setAccessToken(_ token: String) async {
            cachedAccessToken = token
            await MainActor.run {
                try? Keychain.shared.set(token, forKey: Self.accessKey)
            }
        }

        func setRefreshToken(_ token: String) async {
            cachedRefreshToken = token
            await MainActor.run {
                try? Keychain.shared.set(token, forKey: Self.refreshKey)
            }
        }

        func clear() async {
            cachedAccessToken = nil
            cachedRefreshToken = nil
            await MainActor.run {
                try? Keychain.shared.removeValue(forKey: Self.accessKey)
                try? Keychain.shared.removeValue(forKey: Self.refreshKey)
            }
        }
    }

    // MARK: - Refresh Coordinator
    fileprivate actor TokenRefresher {
        static let shared = TokenRefresher()
        private var ongoingTask: Task<TokenResponse, Error>?

        func refreshIfNeeded(session: URLSession, httpHost: String) async throws -> TokenResponse {
            if let ongoingTask {
                return try await ongoingTask.value
            }
            let task = Task { () throws -> TokenResponse in
                defer { self.clearOngoing() }
                return try await self.performRefresh(session: session, httpHost: httpHost)
            }
            ongoingTask = task
            return try await task.value
        }

        private func clearOngoing() {
            ongoingTask = nil
        }

        private func performRefresh(session: URLSession, httpHost: String) async throws -> TokenResponse {
            guard let refreshToken = await AuthTokenStore.shared.getRefreshToken() else {
                throw URLError(.userAuthenticationRequired)
            }
            guard let url = URL(string: httpHost + "api/auth/refresh") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.httpMethod = RequestType.post.rawValue
            request.addValue("application/x-binary-codable", forHTTPHeaderField: "Content-Type")
            request.addValue("application/x-binary-codable", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.upload(for: request, from: Data())
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.userAuthenticationRequired)
            }
            let decoded = try BinaryDecoder().decode(TokenResponse.self, from: data)
            await AuthTokenStore.shared.setAccessToken(decoded.token)
            if let refreshTokenValue = decoded.refreshToken {
                await AuthTokenStore.shared.setRefreshToken(refreshTokenValue)
            }
            return decoded
        }
    }

    /// Warm the in-memory token cache after login/password update (MainActor keychain writes).
    static func persistSession(accessToken: String, refreshToken: String?) async {
        await AuthTokenStore.shared.setAccessToken(accessToken)
        if let refreshToken {
            await AuthTokenStore.shared.setRefreshToken(refreshToken)
        }
    }
    
    func request<T: Codable>(
        method: RequestType = .get,
        httpHost: String,
        url: String,
        headers: [String: String] = [:],
        token: String?,
        body: Data? = nil
    ) async throws -> Response<T> {
        // Build URL (avoid double slashes if httpHost already ends with "/")
        let absolute = httpHost.hasSuffix("/") ? httpHost + url : httpHost + "/" + url
        guard let url = URL(string: absolute) else {
            throw URLError(.badURL)
        }

        // Merge headers and attach bearer if available/not already present
        var mergedHeaders = headers
        if mergedHeaders["Authorization"] == nil {
            if let token = token, !token.isEmpty {
                mergedHeaders["Authorization"] = "Bearer \(token)"
            } else if let stored = await AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
                mergedHeaders["Authorization"] = "Bearer \(stored)"
            }
        }

        // First attempt
        var response: Response<T> = try await request(
            url: url,
            method: method,
            headers: mergedHeaders,
            body: body,
            codableType: .binary)

        // Check for 401 and try refresh once
        if let httpResponse = response.urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            do {
                _ = try await TokenRefresher.shared.refreshIfNeeded(session: self, httpHost: httpHost)
                // Update Authorization header with refreshed access token
                if let newToken = await AuthTokenStore.shared.getAccessToken() {
                    mergedHeaders["Authorization"] = "Bearer \(newToken)"
                }
                response = try await request(
                    url: url,
                    method: method,
                    headers: mergedHeaders,
                    body: body,
                    codableType: .binary)
            } catch {
                // Propagate original 401 response if refresh fails
                return response
            }
        }

        return response
    }

    /// Authenticated JSON request with the same 401 → refresh → retry path as BinaryCodable calls.
    func authenticatedJSONRequest<T: Codable>(
        method: RequestType,
        httpHost: String,
        path: String,
        body: Data? = nil
    ) async throws -> Response<T> {
        let absolute = httpHost.hasSuffix("/") ? httpHost + path : httpHost + "/" + path
        guard let url = URL(string: absolute) else {
            throw URLError(.badURL)
        }

        var headers: [String: String] = [:]
        if let stored = await AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            headers["Authorization"] = "Bearer \(stored)"
        }

        var response: Response<T> = try await request(
            url: url,
            method: method,
            headers: headers,
            body: body,
            codableType: .json)

        if let httpResponse = response.urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            do {
                _ = try await TokenRefresher.shared.refreshIfNeeded(session: self, httpHost: httpHost)
                if let newToken = await AuthTokenStore.shared.getAccessToken() {
                    headers["Authorization"] = "Bearer \(newToken)"
                }
                response = try await request(
                    url: url,
                    method: method,
                    headers: headers,
                    body: body,
                    codableType: .json)
            } catch {
                return response
            }
        }

        return response
    }
    
    enum CodableType {
        case binary, json
    }
    
    func request<T: Codable>(
        url: URL,
        method: RequestType,
        headers: [String: String]? = nil,
        body: Data? = nil,
        codableType: CodableType = .binary
    ) async throws -> Response<T> {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 60 * 5
        if codableType == .json {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
        } else {
            request.addValue("application/x-binary-codable", forHTTPHeaderField: "Content-Type")
            request.addValue("application/x-binary-codable", forHTTPHeaderField: "Accept")
        }
        // Set headers if provided
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        // Perform the network request
        let (data, response) = try await (method == .post || method == .put || method == .delete || method == .patch) ?
            self.upload(for: request, from: body ?? Data()) :
            self.data(for: request)
        // Handle the response
        return try handleResponse(data: data, response: response, codableType: codableType)
    }
    
    private func handleResponse<T: Codable>(data: Data, response: URLResponse, codableType: CodableType) throws -> Response<T> {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Check for successful status codes (2xx)
        guard (200...299).contains(httpResponse.statusCode) else {
            return Response(data: nil, urlResponse: response)
        }
        // Some endpoints may return an empty body (e.g., password update). In that case, avoid decoding.
        if data.isEmpty {
            return Response(data: nil, urlResponse: response)
        }
        // If the caller requested raw Data, just return it without decoding
        if T.self == Data.self {
            // Force-cast is safe by construction
            return Response(data: (data as! T), urlResponse: response)
        }
        let decodedResponse: T
        // Decode the response based on the expected type
        if codableType == .json {
            // API train/job endpoints encode Date as ISO-8601 (see CafePredictorController.jsonResponse).
            // Default JSONDecoder expects reference-date doubles and fails with
            // "The data couldn’t be read because it isn’t in the correct format."
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decodedResponse = try decoder.decode(T.self, from: data)
        } else {
            decodedResponse = try BinaryDecoder().decode(T.self, from: data)
        }
        return Response(data: decodedResponse, urlResponse: response)
    }
    
    static func makeToken(email: String, seed: String) async throws -> String {
        let seedData = Data(seed.utf8)
        guard seedData.count == 32 else {
            throw URLError(.cannotDecodeContentData, userInfo: [NSLocalizedDescriptionKey: "MLDSA seed must be exactly 32 bytes"])
        }
        let keys = JWTKeyCollection()
        let privateKey = try MLDSA87PrivateKey(seedRepresentation: seedData)
        await keys.add(mldsa: privateKey)
        let payload = UserJWT(subject: .init(stringLiteral: email), expiration: .init(value: Date().addingTimeInterval(3600)))
        return try await keys.sign(payload)
    }
    
    struct UserJWT: JWTPayload {
        enum CodingKeys: String, CodingKey {
            case expiration = "exp"
            case subject = "sub"
        }
        var subject: SubjectClaim
        var expiration: ExpirationClaim
        func verify(using signer: some JWTAlgorithm) throws { try expiration.verifyNotExpired() }
    }
}



//
//  R2MediaStorage.swift
//  CafeSmartAPI
//

import Foundation

public struct R2MediaConfig: Sendable, Equatable {
    public var accountId: String
    public var accessKeyId: String
    public var secretAccessKey: String
    public var bucket: String
    public var publicBaseURL: String
    public var endpointHost: String
    public var region: String
    public var cacheMaxAgeSeconds: Int

    public init(
        accountId: String,
        accessKeyId: String,
        secretAccessKey: String,
        bucket: String,
        publicBaseURL: String,
        endpointHost: String? = nil,
        region: String = "auto",
        cacheMaxAgeSeconds: Int = 3600
    ) {
        self.accountId = accountId
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.bucket = bucket
        self.publicBaseURL = publicBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.endpointHost = endpointHost ?? "\(accountId).r2.cloudflarestorage.com"
        self.region = region
        self.cacheMaxAgeSeconds = cacheMaxAgeSeconds
    }

    public static func fromEnvironment(
        _ get: @escaping (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) -> R2MediaConfig? {
        guard let accountId = get("R2_ACCOUNT_ID"), !accountId.isEmpty,
              let accessKeyId = get("R2_ACCESS_KEY_ID"), !accessKeyId.isEmpty,
              let secret = get("R2_SECRET_ACCESS_KEY"), !secret.isEmpty,
              let bucket = get("R2_BUCKET"), !bucket.isEmpty,
              let publicBase = get("R2_PUBLIC_BASE_URL"), !publicBase.isEmpty
        else { return nil }
        let maxAge = Int(get("MEDIA_CACHE_MAX_AGE_SECONDS") ?? "") ?? 3600
        let endpointHost: String? = {
            guard let raw = get("R2_ENDPOINT"), !raw.isEmpty else { return nil }
            if let host = URL(string: raw)?.host { return host }
            return raw
        }()
        return R2MediaConfig(
            accountId: accountId,
            accessKeyId: accessKeyId,
            secretAccessKey: secret,
            bucket: bucket,
            publicBaseURL: publicBase,
            endpointHost: endpointHost,
            region: get("R2_REGION") ?? "auto",
            cacheMaxAgeSeconds: maxAge)
    }
}

public actor R2MediaStorage: MediaStorage {
    private let config: R2MediaConfig
    private let http: any HTTPClientPerforming
    private let now: @Sendable () -> Date

    public init(
        config: R2MediaConfig,
        http: any HTTPClientPerforming,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.http = http
        self.now = now
    }

    public func put(key: String, contentType: String, bytes: [UInt8]) async throws -> MediaPutResult {
        let response = try await signedRequest(
            method: "PUT", key: key, contentType: contentType, body: bytes)
        guard (200..<300).contains(response.status) else {
            throw MediaError.storageFailed("R2 PutObject status \(response.status)")
        }
        return MediaPutResult(
            key: key,
            publicURL: "\(config.publicBaseURL)/\(key)",
            contentType: contentType,
            byteCount: bytes.count)
    }

    public func delete(key: String) async throws {
        let response = try await signedRequest(
            method: "DELETE", key: key, contentType: nil, body: nil)
        guard (200..<300).contains(response.status) || response.status == 404 else {
            throw MediaError.storageFailed("R2 DeleteObject status \(response.status)")
        }
    }

    private func signedRequest(
        method: String, key: String, contentType: String?, body: [UInt8]?
    ) async throws -> MediaHTTPResponse {
        let date = now()
        let (amzDate, dateStamp) = S3SigV4.amzDate(from: date)
        let payloadHash = S3SigV4.hexSHA256(body ?? [])
        let canonicalURI = "/\(config.bucket)" + S3SigV4.canonicalURI(forKey: key)
        // path-style: host is endpoint, URI includes bucket
        var headers: [(String, String)] = [
            ("host", config.endpointHost),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzDate),
        ]
        if method == "PUT" {
            headers.append(("cache-control", "public, max-age=\(config.cacheMaxAgeSeconds)"))
            if let contentType {
                headers.append(("content-type", contentType))
            }
            if let body {
                headers.append(("content-length", String(body.count)))
            }
        }
        headers.sort { $0.0 < $1.0 }
        let canonicalHeaders =
            headers.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = headers.map(\.0).joined(separator: ";")
        let canonical = S3SigV4.canonicalRequest(
            method: method,
            canonicalURI: canonicalURI,
            canonicalQueryString: "",
            canonicalHeaders: canonicalHeaders,
            signedHeaders: signedHeaders,
            payloadHash: payloadHash)
        let auth = S3SigV4.authorizationHeader(
            credentials: .init(
                accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey),
            region: config.region,
            service: "s3",
            amzDate: amzDate,
            dateStamp: dateStamp,
            canonicalRequest: canonical,
            signedHeaders: signedHeaders)
        var headerMap = Dictionary(uniqueKeysWithValues: headers.map { ($0.0, $0.1) })
        headerMap["authorization"] = auth
        // Restore conventional header casing for HTTP client
        var outgoing: [String: String] = [:]
        for (k, v) in headerMap {
            switch k {
            case "host": outgoing["Host"] = v
            case "authorization": outgoing["Authorization"] = v
            case "content-type": outgoing["Content-Type"] = v
            case "content-length": outgoing["Content-Length"] = v
            case "cache-control": outgoing["Cache-Control"] = v
            case "x-amz-content-sha256": outgoing["x-amz-content-sha256"] = v
            case "x-amz-date": outgoing["x-amz-date"] = v
            default: outgoing[k] = v
            }
        }
        let url = "https://\(config.endpointHost)\(canonicalURI)"
        return try await http.execute(
            MediaHTTPRequest(method: method, url: url, headers: outgoing, body: body))
    }
}

public actor URLSessionMediaHTTPClient: HTTPClientPerforming {
    public init() {}

    public func execute(_ request: MediaHTTPRequest) async throws -> MediaHTTPResponse {
        guard let url = URL(string: request.url) else {
            throw MediaError.storageFailed("invalid url")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (k, v) in request.headers {
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }
        if let body = request.body {
            urlRequest.httpBody = Data(body)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return MediaHTTPResponse(status: status, body: Array(data))
    }
}

//
//  S3SigV4.swift
//  CafeSmartAPI
//
//  Pure AWS Signature V4 helpers for R2 S3-compatible Put/Delete.
//

import Crypto
import Foundation

public enum S3SigV4: Sendable {
    public struct Credentials: Sendable {
        public var accessKeyId: String
        public var secretAccessKey: String
        public init(accessKeyId: String, secretAccessKey: String) {
            self.accessKeyId = accessKeyId
            self.secretAccessKey = secretAccessKey
        }
    }

    public static func amzDate(from date: Date) -> (amz: String, short: String) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amz = formatter.string(from: date)
        formatter.dateFormat = "yyyyMMdd"
        let short = formatter.string(from: date)
        return (amz, short)
    }

    public static func hexSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hexSHA256(_ bytes: [UInt8]) -> String {
        hexSHA256(Data(bytes))
    }

    public static func hmacSHA256(key: SymmetricKey, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    public static func hmacSHA256(keyData: Data, string: String) -> Data {
        let key = SymmetricKey(data: keyData)
        return hmacSHA256(key: key, data: Data(string.utf8))
    }

    public static func signingKey(
        secret: String, dateStamp: String, region: String, service: String
    ) -> SymmetricKey {
        let kDate = hmacSHA256(keyData: Data("AWS4\(secret)".utf8), string: dateStamp)
        let kRegion = hmacSHA256(keyData: kDate, string: region)
        let kService = hmacSHA256(keyData: kRegion, string: service)
        let kSigning = hmacSHA256(keyData: kService, string: "aws4_request")
        return SymmetricKey(data: kSigning)
    }

    /// Builds Authorization header for a request with given signed headers (lowercase names, sorted).
    public static func authorizationHeader(
        credentials: Credentials,
        region: String,
        service: String,
        amzDate: String,
        dateStamp: String,
        canonicalRequest: String,
        signedHeaders: String
    ) -> String {
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            hexSHA256(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
        let key = signingKey(
            secret: credentials.secretAccessKey, dateStamp: dateStamp, region: region,
            service: service)
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8), using: key
        ).map { String(format: "%02x", $0) }.joined()
        return
            "\(algorithm) Credential=\(credentials.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    public static func canonicalRequest(
        method: String,
        canonicalURI: String,
        canonicalQueryString: String,
        canonicalHeaders: String,
        signedHeaders: String,
        payloadHash: String
    ) -> String {
        [
            method,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")
    }

    /// URI-encode path segments per AWS (slash preserved as delimiter).
    public static func canonicalURI(forKey key: String) -> String {
        "/"
            + key.split(separator: "/").map { segment in
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-._~")
                return String(segment).addingPercentEncoding(withAllowedCharacters: allowed)
                    ?? String(segment)
            }.joined(separator: "/")
    }
}

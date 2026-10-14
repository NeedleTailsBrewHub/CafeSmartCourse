//
//  BinaryCodable+Extension.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
import BinaryCodable
import NIOCore
import Vapor

/// Vapor ContentEncoder backed by BinaryCodable.
public struct BinaryContentEncoder: ContentEncoder, Sendable {
  public init() {}

  public func encode<E: Encodable>(
    _ encodable: E,
    to body: inout ByteBuffer,
    headers: inout HTTPHeaders
  ) throws {
    let data = try BinaryEncoder().encode(encodable)
    body = ByteBuffer(data: data)
    headers.replaceOrAdd(name: .contentType, value: "application/x-binary-codable")
  }
}

/// Vapor ContentDecoder backed by BinaryCodable.
public struct BinaryContentDecoder: ContentDecoder, Sendable {
  public init() {}

  public func decode<D: Decodable>(
    _ decodable: D.Type,
    from body: ByteBuffer,
    headers: HTTPHeaders
  ) throws -> D {
    var copy = body
    let data = copy.readData(length: copy.readableBytes) ?? Data()
    return try BinaryDecoder().decode(decodable, from: data)
  }
}

/// Marker for types that encode HTTP responses as BinaryCodable payloads.
/// Types that also conform to `Content` must implement `encodeResponse(for:)`
/// themselves (see `binaryEncodedResponse()`) to avoid ambiguity with Content's default.
public protocol BinaryResponseEncodable: AsyncResponseEncodable, Encodable {}

extension Encodable {
  public func binaryEncodedResponse(status: HTTPResponseStatus = .ok) throws -> Response {
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/x-binary-codable")
    let data = try BinaryEncoder().encode(self)
    return .init(status: status, headers: headers, body: .init(data: data))
  }
}

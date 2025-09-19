//
//  BSON+Extension.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
import BSON
import Vapor

extension BSONEncoder: @retroactive ContentEncoder, @unchecked Sendable {
  public func encode<E>(_ encodable: E, to body: inout ByteBuffer, headers: inout HTTPHeaders)
    throws where E: Encodable
  {
    let document = try self.encode(encodable)
    body = document.makeByteBuffer()
    headers.add(name: .contentType, value: "application/bson")
  }
}
extension BSONDecoder: @retroactive ContentDecoder {
  public func decode<D>(_ decodable: D.Type, from body: ByteBuffer, headers: HTTPHeaders) throws
    -> D where D: Decodable
  {
    return try self.decode(decodable, from: Document(buffer: body))
  }
}

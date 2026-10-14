//
//  MLDSASeed.swift
//  CafeSmartApi
//
import Foundation
import Vapor

enum MLDSASeed {
  static let requiredByteCount = 32

  /// Loads a 32-byte MLDSA seed from `MLDSA_SEED` (or legacy `HMAC_SECRET`).
  /// Accepts raw 32 UTF-8 bytes, or a 64-character hex string.
  static func load(from environment: (String) -> String? = Environment.get) throws -> Data {
    let raw = environment("MLDSA_SEED") ?? environment("HMAC_SECRET") ?? ""
    guard !raw.isEmpty else {
      throw Abort(
        .internalServerError,
        reason: "MLDSA_SEED is required (32 bytes, or 64 hex characters). HMAC_SECRET is accepted as a temporary fallback.")
    }

    if raw.count == 64, let hex = Data(hexString: raw) {
      return hex
    }

    let data = Data(raw.utf8)
    guard data.count == requiredByteCount else {
      throw Abort(
        .internalServerError,
        reason: "MLDSA_SEED must be exactly \(requiredByteCount) bytes (or 64 hex characters); got \(data.count).")
    }
    return data
  }
}

private extension Data {
  init?(hexString: String) {
    let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.count % 2 == 0 else { return nil }
    var bytes = [UInt8]()
    bytes.reserveCapacity(cleaned.count / 2)
    var index = cleaned.startIndex
    while index < cleaned.endIndex {
      let next = cleaned.index(index, offsetBy: 2)
      guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}

//
//  MediaImageValidator.swift
//  CafeSmartAPI
//

import Foundation

public enum MediaImageValidator: Sendable {
    public static let defaultMaxBytes = 5_242_880
    public static let defaultMaxPixels = 20_000_000

    public struct Result: Sendable, Equatable {
        public var contentType: String
        public var ext: String
        public var byteCount: Int
    }

    public static func validate(
        bytes: [UInt8],
        declaredContentType: String,
        maxBytes: Int = defaultMaxBytes,
        maxPixels: Int = defaultMaxPixels
    ) throws -> Result {
        guard !bytes.isEmpty else { throw MediaError.emptyBody }
        guard bytes.count <= maxBytes else { throw MediaError.payloadTooLarge(max: maxBytes) }

        let declared = declaredContentType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed: Set<String> = ["image/jpeg", "image/jpg", "image/png", "image/webp"]
        guard allowed.contains(declared) else {
            throw MediaError.unsupportedContentType(declared)
        }

        let sniffed = try sniff(bytes)
        // Normalize jpg
        let declaredNorm = declared == "image/jpg" ? "image/jpeg" : declared
        guard sniffed.contentType == declaredNorm
                || (declaredNorm == "image/jpeg" && sniffed.contentType == "image/jpeg")
        else {
            throw MediaError.magicMismatch
        }

        if let pixels = sniffed.pixelCount, pixels > maxPixels {
            throw MediaError.pixelLimitExceeded
        }

        return Result(
            contentType: sniffed.contentType,
            ext: sniffed.ext,
            byteCount: bytes.count)
    }

    private struct Sniff: Sendable {
        var contentType: String
        var ext: String
        var pixelCount: Int?
    }

    private static func sniff(_ bytes: [UInt8]) throws -> Sniff {
        // PNG
        if bytes.count >= 24,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A
        {
            let w = Int(UInt32(bytes[16]) << 24 | UInt32(bytes[17]) << 16
                | UInt32(bytes[18]) << 8 | UInt32(bytes[19]))
            let h = Int(UInt32(bytes[20]) << 24 | UInt32(bytes[21]) << 16
                | UInt32(bytes[22]) << 8 | UInt32(bytes[23]))
            return Sniff(contentType: "image/png", ext: "png", pixelCount: w * h)
        }
        // JPEG
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            let pixels = jpegPixelCount(bytes)
            return Sniff(contentType: "image/jpeg", ext: "jpg", pixelCount: pixels)
        }
        // WEBP: RIFF....WEBP
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50
        {
            return Sniff(contentType: "image/webp", ext: "webp", pixelCount: nil)
        }
        throw MediaError.magicMismatch
    }

    /// Best-effort SOF scan for width/height.
    private static func jpegPixelCount(_ bytes: [UInt8]) -> Int? {
        var i = 2
        while i + 9 < bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            if marker == 0xD9 || marker == 0xDA { return nil }
            if i + 3 >= bytes.count { return nil }
            let len = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                if i + 8 < bytes.count {
                    let h = Int(bytes[i + 5]) << 8 | Int(bytes[i + 6])
                    let w = Int(bytes[i + 7]) << 8 | Int(bytes[i + 8])
                    return w * h
                }
                return nil
            }
            i += 2 + len
        }
        return nil
    }
}

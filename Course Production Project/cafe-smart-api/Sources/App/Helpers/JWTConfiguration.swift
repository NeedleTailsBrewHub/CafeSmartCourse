//
//  JWTConfiguration.swift
//  CafeSmartAPI
//
//  Post-quantum JWT (ML-DSA-87) via JWTKit `@_spi(PostQuantum)`.
//

@_spi(PostQuantum) import JWTKit
import Vapor

enum JWTConfiguration {
    /// Key id embedded in signed JWTs so verifiers can select ML-DSA-87.
    static let mldsa87Kid = JWKIdentifier(string: "cafesmart-mldsa87")

    /// Install an ML-DSA-87 signer on the app's JWT key collection.
    @available(macOS 26.0, *)
    static func configurePostQuantum(on app: Application) async throws {
        let seed = try MLDSASeed.load()
        // JWTKit 5.6+: `MLDSA87PrivateKey` == `MLDSA.PrivateKey<MLDSA87>`
        let privateKey = try MLDSA87PrivateKey(seedRepresentation: seed)
        await app.jwt.keys.add(mldsa: privateKey, kid: mldsa87Kid)
        app.logger.info("JWT signing configured with ML-DSA-87 (kid=\(mldsa87Kid.string))")
    }
}

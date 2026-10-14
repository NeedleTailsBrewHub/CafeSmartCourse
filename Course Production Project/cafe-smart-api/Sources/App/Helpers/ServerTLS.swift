//
//  ServerTLS.swift
//  CafeSmartAPI
//
//  Shared TLS 1.3 loading for HTTP (Vapor) and WebSocket (CMK).
//

import Foundation
import NIOSSL
import Vapor

enum ServerTLSError: Error, CustomStringConvertible, Equatable {
    case missingProductionCertEnv
    case fileNotFound(String)
    case emptyPath

    var description: String {
        switch self {
        case .missingProductionCertEnv:
            return "Production requires API_LOCAL_FULL_CHAIN and API_LOCAL_PRIV_KEY"
        case .fileNotFound(let path):
            return "TLS certificate file not found: \(path)"
        case .emptyPath:
            return "TLS certificate path is empty"
        }
    }
}

enum ServerTLS {
    struct Paths: Equatable, Sendable {
        let fullChain: String
        let privateKey: String
    }

    /// Resolve env-relative or absolute certificate paths.
    static func resolvePath(
        _ path: String,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.hasPrefix("/") { return trimmed }
        if trimmed.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return (home as NSString).appendingPathComponent(String(trimmed.dropFirst(2)))
        }
        return (workingDirectory as NSString).appendingPathComponent(trimmed)
    }

    static func envPaths(
        chainEnv: String = "API_LOCAL_FULL_CHAIN",
        keyEnv: String = "API_LOCAL_PRIV_KEY",
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> Paths? {
        let chainRaw = Environment.get(chainEnv)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keyRaw = Environment.get(keyEnv)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !chainRaw.isEmpty, !keyRaw.isEmpty else { return nil }
        return Paths(
            fullChain: resolvePath(chainRaw, workingDirectory: workingDirectory),
            privateKey: resolvePath(keyRaw, workingDirectory: workingDirectory))
    }

    static func makeConfiguration(paths: Paths) throws -> TLSConfiguration {
        guard !paths.fullChain.isEmpty, !paths.privateKey.isEmpty else {
            throw ServerTLSError.emptyPath
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.fullChain) else {
            throw ServerTLSError.fileNotFound(paths.fullChain)
        }
        guard fm.fileExists(atPath: paths.privateKey) else {
            throw ServerTLSError.fileNotFound(paths.privateKey)
        }

        let certs = try NIOSSLCertificate.fromPEMFile(paths.fullChain)
            .map { NIOSSLCertificateSource.certificate($0) }
        let privateKey = try NIOSSLPrivateKey(file: paths.privateKey, format: .pem)
        var configuration = TLSConfiguration.makeServerConfiguration(
            certificateChain: certs,
            privateKey: .privateKey(privateKey))
        configuration.minimumTLSVersion = .tlsv13
        configuration.maximumTLSVersion = .tlsv13
        return configuration
    }

    /// Production: TLS required. Development/testing: TLS only when both env paths are set.
    static func configuration(
        for environment: Environment,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) throws -> TLSConfiguration? {
        let paths = envPaths(workingDirectory: workingDirectory)
        if environment == .production {
            guard let paths else { throw ServerTLSError.missingProductionCertEnv }
            return try makeConfiguration(paths: paths)
        }
        guard let paths else { return nil }
        return try makeConfiguration(paths: paths)
    }

    static func makeSSLContext(_ configuration: TLSConfiguration) throws -> NIOSSLContext {
        try NIOSSLContext(configuration: configuration)
    }
}

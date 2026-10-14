//
//  ServerTLSTests.swift
//  ApiTests
//

import Foundation
import NIOSSL
import Testing
import Vapor
@testable import cafe_smart_api

@Suite(.serialized)
struct ServerTLSTests {

    @Test func resolvePathKeepsAbsoluteAndJoinsRelative() {
        let abs = ServerTLS.resolvePath("/etc/ssl/fullchain.pem", workingDirectory: "/app")
        #expect(abs == "/etc/ssl/fullchain.pem")

        let rel = ServerTLS.resolvePath("certs/fullchain.pem", workingDirectory: "/app")
        #expect(rel == "/app/certs/fullchain.pem")
    }

    @Test func productionRequiresCertEnv() throws {
        let previousChain = getenv("API_LOCAL_FULL_CHAIN").map { String(cString: $0) }
        let previousKey = getenv("API_LOCAL_PRIV_KEY").map { String(cString: $0) }
        defer {
            restoreEnv("API_LOCAL_FULL_CHAIN", previousChain)
            restoreEnv("API_LOCAL_PRIV_KEY", previousKey)
        }
        unsetenv("API_LOCAL_FULL_CHAIN")
        unsetenv("API_LOCAL_PRIV_KEY")

        do {
            _ = try ServerTLS.configuration(for: .production)
            Issue.record("Expected missingProductionCertEnv")
        } catch let error as ServerTLSError {
            #expect(error == .missingProductionCertEnv)
        }
    }

    @Test func loadsTLS13ConfigurationFromPEMFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cafesmart-tls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let chain = dir.appendingPathComponent("fullchain.pem").path
        let key = dir.appendingPathComponent("privkey.pem").path
        try Self.generateSelfSignedCert(chainPath: chain, keyPath: key)

        let paths = ServerTLS.Paths(fullChain: chain, privateKey: key)
        let configuration = try ServerTLS.makeConfiguration(paths: paths)
        #expect(configuration.minimumTLSVersion == .tlsv13)
        #expect(configuration.maximumTLSVersion == .tlsv13)
        let context = try ServerTLS.makeSSLContext(configuration)
        _ = try NIOSSLServerHandler(context: context)
    }

    @Test func developmentSkipsTLSWhenEnvUnset() throws {
        let previousChain = getenv("API_LOCAL_FULL_CHAIN").map { String(cString: $0) }
        let previousKey = getenv("API_LOCAL_PRIV_KEY").map { String(cString: $0) }
        defer {
            restoreEnv("API_LOCAL_FULL_CHAIN", previousChain)
            restoreEnv("API_LOCAL_PRIV_KEY", previousKey)
        }
        unsetenv("API_LOCAL_FULL_CHAIN")
        unsetenv("API_LOCAL_PRIV_KEY")

        let configuration = try ServerTLS.configuration(for: .development)
        #expect(configuration == nil)
    }

    private func restoreEnv(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }

    private static func generateSelfSignedCert(chainPath: String, keyPath: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        proc.arguments = [
            "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", keyPath,
            "-out", chainPath,
            "-days", "1",
            "-nodes",
            "-subj", "/CN=localhost",
        ]
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            throw NSError(
                domain: "ServerTLSTests", code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "openssl failed"])
        }
    }
}

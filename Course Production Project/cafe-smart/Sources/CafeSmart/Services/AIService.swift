//
//  AIService.swift
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

#if canImport(CoreML)
import CoreML
#if SKIP
import SkipFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BSON

actor AIService {
    static let shared = AIService()
    
    private func modelIdString(_ artifact: MLModelArtifact) -> String {
        if let id = artifact.id { return id }
        if let oid = artifact._id { return oid.hexString }
        return ""
    }
    
    func fetchCSVFile(from url: URL) async throws -> URL {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        
        // Download directly to a temp file
        let (tmpLocation, response) = try await URLSession.shared.download(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Try to use server-provided filename from Content-Disposition
        let filename = filenameFromContentDisposition(http.allHeaderFields["Content-Disposition"] as? String)
            ?? "download.csv"

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename, conformingTo: .commaSeparatedText)

        // Move (replace if exists)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmpLocation, to: destination)
        return destination
    }
    
    private func filenameFromContentDisposition(_ header: String?) -> String? {
        guard let header else { return nil }

        // RFC 5987/6266: try filename*=
        if let range = header.range(of: #"filename\*=\s*[^']*'[^']*'([^;]+)"#, options: .regularExpression) {
            let encoded = String(header[range]).split(separator: "'").last.map(String.init)
            return encoded?.removingPercentEncoding
        }

        // Fallback: filename=
        if let range = header.range(of: #"filename="?([^";]+)"?"#, options: .regularExpression),
           let match = header[range].split(separator: "=").last {
            return match.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }
    
    // ModelUploadResponse moved to Models/AIModels.swift

    /// Upload a `.mlmodel` file as raw bytes (application/octet-stream). Optional fields go via query params.
    func uploadMLModel(from fileURL: URL, name: String? = nil, runtime: String? = nil, kind: String? = nil) async throws {
        let base = await Constants.httpHost + "api/auth/predictor/models/upload"
        guard var comps = URLComponents(string: base) else { throw URLError(.badURL) }
        var query: [URLQueryItem] = []
        if let name {
            query.append(URLQueryItem(name: "name", value: name))
        }
        if let runtime {
            query.append(URLQueryItem(name: "runtime", value: runtime))
        }
        if let kind {
            query.append(URLQueryItem(name: "kind", value: kind))
        }
        if !query.isEmpty {
            comps.queryItems = query
        }
        guard let url = comps.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 * 10
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Model upload failed (status: \(status))"])
        }
    }

    // MARK: - Models: list, activate, instantiate

    // MLModelArtifact and ModelsList moved to Models/AIModels.swift

    func listModels() async throws -> [MLModelArtifact] {
        var request = URLRequest(url: URL(string: "\(await Constants.httpHost)api/auth/predictor/models")!)
        request.httpMethod = "GET"
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try BSONDecoder().decode(ModelsList.self, from: Document(data: data)).items
    }

    func activateModel(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(await Constants.httpHost)api/auth/predictor/models/activate")!)
        request.httpMethod = "POST"
        request.setValue("application/bson", forHTTPHeaderField: "Content-Type")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try BSONEncoder().encode(["id": id]).makeData()
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func instantiatePredictor(kind: String) async throws {
        var request = URLRequest(url: URL(string: "\(await Constants.httpHost)api/auth/predictor/instantiate")!)
        request.httpMethod = "POST"
        request.setValue("application/bson", forHTTPHeaderField: "Content-Type")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try BSONEncoder().encode(["kind": kind]).makeData()
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // Ensure an active restockDaily model and an instantiated predictor
    func prepareRestockPredictor() async throws {
        let models = try await listModels()
        guard let latest = models.last(where: { $0.kind == .restockDaily }) else {
            throw URLError(.resourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "No restockDaily model found. Upload a model first."])
        }
        if !latest.active {
            let id = modelIdString(latest)
            guard !id.isEmpty else { throw URLError(.badServerResponse) }
            try await activateModel(id: id)
        }
        try await instantiatePredictor(kind: "restockDaily")
    }

    // MARK: - Restock decision (server-side)

    // RestockDecisionRequest/Response moved to Models/AIModels.swift

    func decideRestock(sku: String, daysAhead: Int? = 7) async throws -> RestockDecisionResponse {
        var request = URLRequest(url: URL(string: "\(await Constants.httpHost)api/auth/predictor/restock/decide")!)
        request.httpMethod = "POST"
        request.setValue("application/bson", forHTTPHeaderField: "Content-Type")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try BSONEncoder().encode(RestockDecisionRequest(sku: sku, daysAhead: daysAhead)).makeData()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try BSONDecoder().decode(RestockDecisionResponse.self, from: Document(data: data))
    }
}
#endif

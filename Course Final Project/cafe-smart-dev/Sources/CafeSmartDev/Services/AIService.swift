//
//  AIService.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/17/25.
//
#if SKIP
import SkipFoundation
#else
import Foundation
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BinaryCodable

actor AIService {

    static let shared = AIService()

    /// Ungated entry for mobile/admin server training (no CoreML required).
    @discardableResult
    func trainRestockOnServer(
        onStatus: (@Sendable (TrainJobDTO) -> Void)? = nil
    ) async throws -> String {
        let job = try await startServerTraining(kind: "restockDaily", onStatus: onStatus)
        return "Server training succeeded (\(job.artifactId ?? job.id))"
    }

    func fetchCapabilities() async throws -> PredictorCapabilities {
        let httpHost = await Constants.httpHost
        let response: Response<PredictorCapabilities> = try await URLSession.shared.authenticatedJSONRequest(
            method: .get,
            httpHost: httpHost,
            path: "api/auth/predictor/capabilities")
        let status = (response.urlResponse as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status), let caps = response.data else {
            throw URLError(
                .badServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "Capabilities failed (\(status))"])
        }
        return caps
    }

    private struct ActivateModelBody: Codable, Sendable {
        let id: String
    }

    private struct DeleteModelBody: Codable, Sendable {
        let id: String
    }

    func fetchCSVFile(from url: URL) async throws -> URL {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }

        let (tempLocation, response) = try await URLSession.shared.download(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let filename = filenameFromContentDisposition(http.allHeaderFields["Content-Disposition"] as? String) ?? "download.csv"

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename, conformingTo: .commaSeparatedText)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempLocation, to: destination)
        return destination
    }

    @discardableResult
    func startServerTraining(
        kind: String = "restockDaily",
        onStatus: (@Sendable (TrainJobDTO) -> Void)? = nil
    ) async throws -> TrainJobDTO {
        let httpHost = await Constants.httpHost
        if await URLSession.AuthTokenStore.shared.getAccessToken()?.isEmpty != false {
            throw URLError(
                .userAuthenticationRequired,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in or session expired — sign in again"])
        }
        let body = try JSONEncoder().encode(["kind": kind])
        let response: Response<TrainJobDTO> = try await URLSession.shared.authenticatedJSONRequest(
            method: .post,
            httpHost: httpHost,
            path: "api/auth/predictor/train",
            body: body)
        let status = (response.urlResponse as? HTTPURLResponse)?.statusCode ?? -1
        if status == 503 {
            throw URLError(.cannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: "Server training unavailable"])
        }
        if status == 401 {
            throw URLError(
                .userAuthenticationRequired,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in or session expired — sign in again"])
        }
        guard (200...299).contains(status), var job = response.data else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Train start failed (\(status))"])
        }
        logger.info("Server train job started id=\(job.id) status=\(job.status)")
        onStatus?(job)
        for _ in 0..<120 {
            if job.status == "succeeded" || job.status == "failed" { break }
            try await Task.sleep(for: .seconds(1))
            job = try await fetchTrainJob(id: job.id)
            onStatus?(job)
        }
        if job.status == "failed" {
            throw URLError(.cannotParseResponse, userInfo: [NSLocalizedDescriptionKey: job.error ?? "Training failed"])
        }
        guard job.status == "succeeded" else {
            throw URLError(
                .timedOut,
                userInfo: [NSLocalizedDescriptionKey: "Training timed out (last status=\(job.status))"])
        }
        return job
    }

    func fetchTrainJob(id: String) async throws -> TrainJobDTO {
        let httpHost = await Constants.httpHost
        let response: Response<TrainJobDTO> = try await URLSession.shared.authenticatedJSONRequest(
            method: .get,
            httpHost: httpHost,
            path: "api/auth/predictor/train/\(id)")
        let status = (response.urlResponse as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status), let job = response.data else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Train status failed (\(status))"])
        }
        return job
    }

    func listTrainJobs() async throws -> [TrainJobDTO] {
        let httpHost = await Constants.httpHost
        let response: Response<TrainJobListDTO> = try await URLSession.shared.authenticatedJSONRequest(
            method: .get,
            httpHost: httpHost,
            path: "api/auth/predictor/train")
        let status = (response.urlResponse as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status), let list = response.data else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "List train jobs failed (\(status))"])
        }
        return list.items
    }

    func listModels() async throws -> [MLModelArtifact] {
        var request = URLRequest(url: URL(string: "\(await Constants.httpHost)api/auth/predictor/models")!)
        request.httpMethod = "GET"
        request.setValue("application/x-binary-codable", forHTTPHeaderField: "Accept")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try BinaryDecoder().decode(ModelsList.self, from: data).items
    }

    func activateModel(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(await Constants.httpHost)api/auth/predictor/models/activate")!)
        request.httpMethod = "POST"
        request.setValue("application/x-binary-codable", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-binary-codable", forHTTPHeaderField: "Accept")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try BinaryEncoder().encode(ActivateModelBody(id: id))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Activate failed (\(code))"])
        }
    }

    func deleteModel(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(await Constants.httpHost)api/auth/predictor/models/delete")!)
        request.httpMethod = "POST"
        request.setValue("application/x-binary-codable", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-binary-codable", forHTTPHeaderField: "Accept")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            request.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try BinaryEncoder().encode(DeleteModelBody(id: id))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let reason = code == 409
                ? "Cannot delete the active model; activate another first"
                : "Delete failed (\(code))"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

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

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60 * 10
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let stored = await URLSession.AuthTokenStore.shared.getAccessToken(), !stored.isEmpty {
            req.setValue("Bearer \(stored)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.upload(for: req, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func filenameFromContentDisposition(_ header: String?) -> String? {
        guard let header else { return nil }

        if let range = header.range(of: #"filename\*=\s*[^']*'[^']*'([^;]+)"#, options: .regularExpression) {
            let encoded = String(header[range]).split(separator: "'").last.map(String.init)
            return encoded?.removingPercentEncoding
        }

        if let range = header.range(of: #"filename="?([^";]+)"?"#, options: .regularExpression),
           let match = header[range].split(separator: "=").last {
            return match.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }
}

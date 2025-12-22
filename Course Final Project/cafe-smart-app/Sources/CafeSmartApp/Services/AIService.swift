//
//  AIService.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/17/25.
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
}
#endif

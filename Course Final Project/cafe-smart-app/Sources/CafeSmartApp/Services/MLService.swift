//
//  MLService.swift
//  cafe-smart-app
//
//  Created by Cole M on 9/17/25.
//
#if canImport(CoreML) 
import CoreML
#if os(macOS) && canImport(CreateML)
import CreateML
import TabularData
#endif
import Foundation

actor MLService {
    
    private let fileURL: URL
    
    enum Errors: Error {
        case invalidURL, modelNotFound, notUpdatable, notWritable, notSupported, insufficientData(String)
    }
    
    
    enum Dataset {
        case ingredientDaily(sku: String?)
        
        var queryItems: [URLQueryItem] {
            switch self {
            case .ingredientDaily(let sku):
                var items = [URLQueryItem(name: "dataset", value: "ingredientDaily")]
                if let sku { items.append(URLQueryItem(name: "sku", value: sku)) }
                return items
            }
        }
    }
    
    init(dataset: Dataset) async throws {
        guard var components = URLComponents(string: "\(await Constants.httpHost)api/auth/predictor/export") else {
            throw Errors.invalidURL
        }
        components.queryItems = dataset.queryItems
        guard let url = components.url else { throw Errors.invalidURL }
        self.fileURL = try await AIService.shared.fetchCSVFile(from: url)
    }
    
    init() async throws {
        guard var components = URLComponents(string: "\(await Constants.httpHost)api/auth/predictor/export") else {
            throw Errors.invalidURL
        }
        components.queryItems = Dataset.ingredientDaily(sku: nil).queryItems
        guard let url = components.url else { throw Errors.invalidURL }
        self.fileURL = try await AIService.shared.fetchCSVFile(from: url)
    }
    
    
    func startTraining() async {
        do {
            let modelName = "restockDaily"
            let modelFileURL = try await self.createModelFile(withCSVAt: fileURL, modelName: modelName)
            try await AIService.shared.uploadMLModel(from: modelFileURL, name: modelName, runtime: "coreml", kind: "restockDaily")
        } catch {
            //log
        }
    }
    
    
    func createModelFile(withCSVAt csvURL: URL, modelName: String) async throws -> URL {
#if os(macOS) && canImport(CreateML)
        let raw = try String(contentsOf: csvURL, encoding: .utf8)
        
        guard let headerLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) else {
            throw Errors.insufficientData("Missing header in CSV")
        }
        let headerCols = headerLine.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard headerCols.count >= 2 else {
            throw Errors.insufficientData("Insufficient columns in CSV header")
        }
        let target = headerCols.last!
        // Use all columns except the target, and drop raw date/datetime and boolean is_weekend (unsupported feature types for CreateML)
        // Server provides year/month/day/weekday so dropping date/is_weekend is fine
        let featureColumns = Array(headerCols.dropLast()).filter { !["date", "datetime", "is_weekend"].contains($0) }
        
        // Choose task type based on target column values
        let isNumericTarget = try csvTargetLooksNumeric(csvURL)
        let stats = try self.csvTargetStats(csvURL)
        logger.info("MLService: dataset=\(modelName) target=\(target) task=\(isNumericTarget ? "regression" : "classification") rows=\(stats.rowCount)")
        
        if !isNumericTarget {
            if stats.rowCount < 10 {
                logger.warning("Warning: training classification with very small dataset (\(stats.rowCount) rows). Results may be poor.")
            }
            if stats.labels.count < 2 {
                throw Errors.insufficientData("Classification requires at least two classes; found \(stats.labels.count).")
            }
        } else {
            if stats.rowCount < 2 {
                throw Errors.insufficientData("Regression requires at least 2 rows; found \(stats.rowCount).")
            }
        }
        
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(modelName).mlmodel")
        try? FileManager.default.removeItem(at: outURL)
        
        var df = try DataFrame(contentsOfCSVFile: csvURL)
        let selectedColumns = featureColumns + [target]
        df = df[selectedColumns]
        logger.info("MLService: using \(featureColumns.count) features: \(featureColumns.joined(separator: ", "))")
        let metadata = MLModelMetadata(
            author: "CafeSmart",
            shortDescription: "Auto-trained model \(modelName) from CSV",
            version: "1.0"
        )
        
        if isNumericTarget {
            let model = try MLRegressor(
                trainingData: df,
                targetColumn: target,
                featureColumns: featureColumns)
            try model.write(to: outURL, metadata: metadata)
        } else {
            let model = try MLClassifier(
                trainingData: df,
                targetColumn: target,
                featureColumns: featureColumns)
            try model.write(to: outURL, metadata: metadata)
        }
        return outURL
#else
        throw Errors.notSupported
#endif
    }
    
    
    // Helper: detect whether target column (last column) appears numeric from CSV contents
    private func csvTargetLooksNumeric(_ url: URL) throws -> Bool {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var lines = raw.split(whereSeparator: \.isNewline).map { String($0) }
        guard lines.count >= 2 else { return false }
        lines.removeFirst() // drop header
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            guard let last = parts.last else { continue }
            return Double(last) != nil
        }
        return false
    }
    
    // Helper: compute total rows and label distribution for the last column
    private func csvTargetStats(_ url: URL) throws -> (rowCount: Int, labels: [String: Int]) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var lines = raw.split(whereSeparator: \.isNewline).map { String($0) }
        guard !lines.isEmpty else { return (0, [:]) }
        lines.removeFirst() // header
        var total = 0
        var counts: [String: Int] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            if let last = parts.last {
                counts[last, default: 0] += 1
                total += 1
            }
        }
        return (total, counts)
    }
}
#endif

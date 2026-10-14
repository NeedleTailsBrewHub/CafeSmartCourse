import Foundation
import Vapor

enum ModelUploadSupport {
    static func defaultRuntime() -> PredictRuntime {
        #if canImport(CoreML)
        return .coreml
        #else
        return .onnx
        #endif
    }

    static func parseRuntime(_ raw: String?) throws -> PredictRuntime {
        guard let raw, !raw.isEmpty else {
            return defaultRuntime()
        }
        guard let runtime = PredictRuntime(rawValue: raw) else {
            throw Abort(.badRequest, reason: "Invalid runtime '\(raw)'. Expected onnx|coreml")
        }
        try PredictorFactory.assertRuntimeSupported(runtime)
        return runtime
    }

    /// Only enum raw values are allowed as directory segments.
    static func sanitizedRuntimePathComponent(_ runtime: PredictRuntime) -> String {
        runtime.rawValue
    }

    static func sanitizedFilename(_ providedName: String, runtime: PredictRuntime) throws -> String {
        var name = providedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = runtime == .onnx ? "model.onnx" : "model.mlmodel"
        }
        if name.contains("/") || name.contains("\\") || name.contains("..") || name.contains("\0") {
            throw Abort(.badRequest, reason: "Invalid model filename")
        }
        let lower = name.lowercased()
        switch runtime {
        case .coreml:
            if !(lower.hasSuffix(".mlmodel") || lower.hasSuffix(".mlmodelc")) {
                name += ".mlmodel"
            }
        case .onnx:
            if lower.hasSuffix(".mlmodel") || lower.hasSuffix(".mlmodelc") {
                throw Abort(.badRequest, reason: "ONNX runtime requires a .onnx file")
            }
            if !lower.hasSuffix(".onnx") {
                name += ".onnx"
            }
        }
        return name
    }

    static func modelsRoot(workingDirectory: String, runtime: PredictRuntime, kind: PredictorKind) -> String {
        let root = workingDirectory.hasSuffix("/") ? workingDirectory : workingDirectory + "/"
        return root + "Models/" + sanitizedRuntimePathComponent(runtime) + "/" + kind.rawValue + "/"
    }
}

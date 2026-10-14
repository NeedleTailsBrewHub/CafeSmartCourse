import Foundation
import Vapor

enum PredictorFactory {
    /// Test hook: when set, `make` throws this error (used for rollback coverage).
    nonisolated(unsafe) static var testingForceMakeError: (any Error)?
    /// When true, clear `testingForceMakeError` after a single throw so restore can succeed.
    nonisolated(unsafe) static var testingForceMakeErrorOnce = false

    static var coremlAvailable: Bool {
        #if canImport(CoreML)
        true
        #else
        false
        #endif
    }

    static var onnxAvailable: Bool {
        #if canImport(CONNX)
        true
        #else
        false
        #endif
    }

    private static var useTestDoubles: Bool {
        let v = (Environment.get("USE_TEST_STORE") ?? "").lowercased()
        return v == "true" || v == "1" || v == "yes"
    }

    static func make(runtime: PredictRuntime, path: String) async throws -> any PredictorServing {
        if let forced = testingForceMakeError {
            if testingForceMakeErrorOnce {
                testingForceMakeError = nil
                testingForceMakeErrorOnce = false
            }
            throw forced
        }
        if useTestDoubles {
            _ = runtime
            _ = path
            return MockPredictor(output: [1.0], outputName: RestockFeatureContract.targetName)
        }
        switch runtime {
        case .coreml:
            #if canImport(CoreML)
            return try await CoreMLPredictor(modelPath: path)
            #else
            throw PredictorError.unavailable(.coreml)
            #endif
        case .onnx:
            #if canImport(CONNX)
            return try await ONNXPredictor(modelPath: path)
            #else
            throw PredictorError.unavailable(.onnx)
            #endif
        }
    }

    static func assertRuntimeSupported(_ runtime: PredictRuntime) throws {
        switch runtime {
        case .coreml where !coremlAvailable:
            throw PredictorError.unavailable(.coreml)
        case .onnx where !onnxAvailable:
            throw PredictorError.unavailable(.onnx)
        default:
            break
        }
    }
}

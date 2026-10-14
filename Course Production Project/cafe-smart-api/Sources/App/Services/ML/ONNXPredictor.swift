#if canImport(CONNX)
import Foundation
import CONNX

actor ONNXPredictor: PredictorServing {
    private let session: OrtSession

    init(modelPath: String, contract: FeatureContractSpec = RestockFeatureContract.spec) async throws {
        do {
            self.session = try OrtSession(modelPath: modelPath)
        } catch {
            throw PredictorError.unsupportedModel("Failed to load ONNX model at \(modelPath): \(error)")
        }
        // Soft contract check when names look tabular.
        let names = Set(session.inputNames)
        let required = contract.requiredInputNames
        let missing = required.filter { !names.contains($0) }
        if !missing.isEmpty && names.count >= 3 {
            // Only enforce when the model appears to be a multi-feature tabular graph.
            if names.intersection(required).count >= 3 {
                throw PredictorError.unsupportedModel(
                    "ONNX model missing required inputs (\(contract.targetName)): \(missing.joined(separator: ", "))"
                )
            }
        }
    }

    func ioNames() async throws -> (input: String, output: String) {
        let input = session.inputNames.first ?? "input"
        let output = session.outputNames.first ?? "output"
        return (input, output)
    }

    func predictMultiple(inputs: [String: PredictorFeature], outputName: String) async throws -> [Float] {
        var tensors: [String: OrtTensorValue] = [:]
        let shape: [Int64] = [1, 1]

        for (name, feature) in inputs {
            let elem = session.inputTypes[name] ?? ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
            switch (elem, feature) {
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING, .string(let s)):
                tensors[name] = .string(s, shape: shape)
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, .int(let v)):
                tensors[name] = .int64([Int64(v)], shape: shape)
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, .double(let v)):
                tensors[name] = .int64([Int64(v)], shape: shape)
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE, .double(let v)):
                tensors[name] = .double([v], shape: shape)
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE, .int(let v)):
                tensors[name] = .double([Double(v)], shape: shape)
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, .double(let v)):
                tensors[name] = .float([Float(v)], shape: shape)
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, .int(let v)):
                tensors[name] = .float([Float(v)], shape: shape)
            case (_, .floats(let arr)):
                tensors[name] = .float(arr, shape: [Int64(arr.count)])
            case (ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING, _):
                throw PredictorError.msg("Feature '\(name)' must be a string for this ONNX model")
            default:
                // Fallback: coerce numerics to float
                switch feature {
                case .double(let v): tensors[name] = .float([Float(v)], shape: shape)
                case .int(let v): tensors[name] = .float([Float(v)], shape: shape)
                case .string(let s): tensors[name] = .string(s, shape: shape)
                case .floats(let arr): tensors[name] = .float(arr, shape: [Int64(arr.count)])
                }
            }
        }

        let resolvedOutput = outputName.isEmpty ? (session.outputNames.first ?? "output") : outputName
        do {
            return try session.run(inputs: tensors, outputName: resolvedOutput)
        } catch {
            throw PredictorError.msg("ONNX run failed: \(error)")
        }
    }
}
#endif

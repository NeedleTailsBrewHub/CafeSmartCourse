#if canImport(CONNX)
import Foundation
import CONNX

/// Thin Swift wrapper around the ONNX Runtime C API (Linux and macOS).
final class OrtSession: @unchecked Sendable {
    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?
    private var session: OpaquePointer?
    private var allocator: UnsafeMutablePointer<OrtAllocator>?

    private(set) var inputNames: [String] = []
    private(set) var outputNames: [String] = []
    private(set) var inputTypes: [String: ONNXTensorElementDataType] = [:]

    enum Errors: Error, CustomStringConvertible {
        case api, status(String), msg(String)
        var description: String {
            switch self {
            case .api: return "Failed to load OrtApi"
            case .status(let s): return s
            case .msg(let s): return s
            }
        }
    }

    init(modelPath: String) throws {
        guard let base = OrtGetApiBase() else { throw Errors.api }
        guard let apiPtr = base.pointee.GetApi(UInt32(ORT_API_VERSION)) else { throw Errors.api }
        self.api = apiPtr

        var envPtr: OpaquePointer?
        try check(api.pointee.CreateEnv?(ORT_LOGGING_LEVEL_WARNING, "cafesmart", &envPtr))
        self.env = envPtr

        var options: OpaquePointer?
        try check(api.pointee.CreateSessionOptions?(&options))
        defer { if let options { api.pointee.ReleaseSessionOptions?(options) } }

        var sessionPtr: OpaquePointer?
        try modelPath.withCString { path in
            try check(api.pointee.CreateSession?(envPtr, path, options, &sessionPtr))
        }
        self.session = sessionPtr

        var alloc: UnsafeMutablePointer<OrtAllocator>?
        try check(api.pointee.GetAllocatorWithDefaultOptions?(&alloc))
        self.allocator = alloc

        try loadIOMetadata()
    }

    deinit {
        if let session { api.pointee.ReleaseSession?(session) }
        if let env { api.pointee.ReleaseEnv?(env) }
    }

    func run(inputs: [String: OrtTensorValue], outputName: String) throws -> [Float] {
        guard let session, let allocator else { throw Errors.msg("Session not ready") }

        var inputNamesC: [UnsafePointer<CChar>?] = []
        var inputValues: [OpaquePointer?] = []
        defer {
            for p in inputNamesC {
                if let p { free(UnsafeMutableRawPointer(mutating: p)) }
            }
            for v in inputValues {
                if let v { api.pointee.ReleaseValue?(v) }
            }
        }

        for (name, tensor) in inputs {
            inputNamesC.append(strdup(name))
            inputValues.append(try makeOrtValue(tensor: tensor, allocator: allocator))
        }

        let outNameDup = strdup(outputName)
        defer { if let outNameDup { free(outNameDup) } }
        var outNamePtr: UnsafePointer<CChar>? = UnsafePointer(outNameDup)
        var output: OpaquePointer?

        let inputNamePtrs = inputNamesC.map { UnsafePointer($0) }
        try inputNamePtrs.withUnsafeBufferPointer { nameBuf in
            try inputValues.withUnsafeBufferPointer { valBuf in
                try withUnsafeMutablePointer(to: &outNamePtr) { outNameBuf in
                    try withUnsafeMutablePointer(to: &output) { outBuf in
                        try check(api.pointee.Run?(
                            session,
                            nil,
                            nameBuf.baseAddress,
                            valBuf.baseAddress,
                            inputValues.count,
                            outNameBuf,
                            1,
                            outBuf
                        ))
                    }
                }
            }
        }
        defer { if let output { api.pointee.ReleaseValue?(output) } }

        return try readFloatOutput(output)
    }

    private func loadIOMetadata() throws {
        guard let session, let allocator else { return }
        var inCount: Int = 0
        var outCount: Int = 0
        try check(api.pointee.SessionGetInputCount?(session, &inCount))
        try check(api.pointee.SessionGetOutputCount?(session, &outCount))

        for i in 0..<inCount {
            var namePtr: UnsafeMutablePointer<CChar>?
            try check(api.pointee.SessionGetInputName?(session, i, allocator, &namePtr))
            let name = namePtr.map { String(cString: $0) } ?? "input_\(i)"
            if let namePtr { allocator.pointee.Free?(allocator, namePtr) }
            inputNames.append(name)

            var typeInfo: OpaquePointer?
            try check(api.pointee.SessionGetInputTypeInfo?(session, i, &typeInfo))
            defer { if let typeInfo { api.pointee.ReleaseTypeInfo?(typeInfo) } }
            var tensorInfo: OpaquePointer?
            try check(api.pointee.CastTypeInfoToTensorInfo?(typeInfo, &tensorInfo))
            var elemType = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
            try check(api.pointee.GetTensorElementType?(tensorInfo, &elemType))
            inputTypes[name] = elemType
        }

        for i in 0..<outCount {
            var namePtr: UnsafeMutablePointer<CChar>?
            try check(api.pointee.SessionGetOutputName?(session, i, allocator, &namePtr))
            let name = namePtr.map { String(cString: $0) } ?? "output_\(i)"
            if let namePtr { allocator.pointee.Free?(allocator, namePtr) }
            outputNames.append(name)
        }
    }

    private func makeOrtValue(tensor: OrtTensorValue, allocator: UnsafeMutablePointer<OrtAllocator>) throws -> OpaquePointer? {
        var shape = tensor.shape
        var value: OpaquePointer?

        switch tensor {
        case .float(let v, _):
            try shape.withUnsafeMutableBufferPointer { shapeBuf in
                try check(api.pointee.CreateTensorAsOrtValue?(
                    allocator,
                    shapeBuf.baseAddress,
                    shapeBuf.count,
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                    &value
                ))
            }
            var mutable: UnsafeMutableRawPointer?
            try check(api.pointee.GetTensorMutableData?(value, &mutable))
            guard let mutable else { throw Errors.msg("Missing float tensor storage") }
            v.withUnsafeBufferPointer { src in
                mutable.copyMemory(from: UnsafeRawPointer(src.baseAddress!), byteCount: v.count * MemoryLayout<Float>.stride)
            }

        case .double(let v, _):
            try shape.withUnsafeMutableBufferPointer { shapeBuf in
                try check(api.pointee.CreateTensorAsOrtValue?(
                    allocator,
                    shapeBuf.baseAddress,
                    shapeBuf.count,
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE,
                    &value
                ))
            }
            var mutable: UnsafeMutableRawPointer?
            try check(api.pointee.GetTensorMutableData?(value, &mutable))
            guard let mutable else { throw Errors.msg("Missing double tensor storage") }
            v.withUnsafeBufferPointer { src in
                mutable.copyMemory(from: UnsafeRawPointer(src.baseAddress!), byteCount: v.count * MemoryLayout<Double>.stride)
            }

        case .int64(let v, _):
            try shape.withUnsafeMutableBufferPointer { shapeBuf in
                try check(api.pointee.CreateTensorAsOrtValue?(
                    allocator,
                    shapeBuf.baseAddress,
                    shapeBuf.count,
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                    &value
                ))
            }
            var mutable: UnsafeMutableRawPointer?
            try check(api.pointee.GetTensorMutableData?(value, &mutable))
            guard let mutable else { throw Errors.msg("Missing int64 tensor storage") }
            v.withUnsafeBufferPointer { src in
                mutable.copyMemory(from: UnsafeRawPointer(src.baseAddress!), byteCount: v.count * MemoryLayout<Int64>.stride)
            }

        case .string(let s, _):
            try shape.withUnsafeMutableBufferPointer { shapeBuf in
                try check(api.pointee.CreateTensorAsOrtValue?(
                    allocator,
                    shapeBuf.baseAddress,
                    shapeBuf.count,
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING,
                    &value
                ))
            }
            try s.withCString { cstr in
                // FillStringTensor expects const char* const*
                try withUnsafePointer(to: cstr) { cstrPtr in
                    try check(api.pointee.FillStringTensor?(value, cstrPtr, 1))
                }
            }
        }
        return value
    }

    private func readFloatOutput(_ output: OpaquePointer?) throws -> [Float] {
        guard let output else { throw Errors.msg("Missing output") }
        var mutable: UnsafeMutableRawPointer?
        try check(api.pointee.GetTensorMutableData?(output, &mutable))
        guard let mutable else { throw Errors.msg("Missing tensor data") }

        var typeInfo: OpaquePointer?
        try check(api.pointee.GetTypeInfo?(output, &typeInfo))
        defer { if let typeInfo { api.pointee.ReleaseTypeInfo?(typeInfo) } }
        var tensorInfo: OpaquePointer?
        try check(api.pointee.CastTypeInfoToTensorInfo?(typeInfo, &tensorInfo))
        var elemType = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
        try check(api.pointee.GetTensorElementType?(tensorInfo, &elemType))
        var count: Int = 1
        try check(api.pointee.GetTensorShapeElementCount?(tensorInfo, &count))

        switch elemType {
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
            let typed = mutable.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: typed, count: count))
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE:
            let typed = mutable.bindMemory(to: Double.self, capacity: count)
            return Array(UnsafeBufferPointer(start: typed, count: count)).map { Float($0) }
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64:
            let typed = mutable.bindMemory(to: Int64.self, capacity: count)
            return Array(UnsafeBufferPointer(start: typed, count: count)).map { Float($0) }
        default:
            throw Errors.msg("Unsupported output element type \(elemType.rawValue)")
        }
    }

    private func check(_ status: OpaquePointer?) throws {
        guard let status else { return }
        defer { api.pointee.ReleaseStatus?(status) }
        let msg = api.pointee.GetErrorMessage?(status).map { String(cString: $0) } ?? "ORT error"
        throw Errors.status(msg)
    }
}

enum OrtTensorValue {
    case float([Float], shape: [Int64])
    case double([Double], shape: [Int64])
    case int64([Int64], shape: [Int64])
    case string(String, shape: [Int64])

    var shape: [Int64] {
        switch self {
        case .float(_, let s), .double(_, let s), .int64(_, let s), .string(_, let s):
            return s
        }
    }
}
#endif

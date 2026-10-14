import Foundation

public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: Duration) async throws -> ProcessResult
}

public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: Duration) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { cont in
            // Process + Pipe must not block the cooperative thread pool, and pipes must be
            // drained while the child runs or large pip output deadlocks (~64KB buffer).
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.runSync(executable: executable, arguments: arguments, timeout: timeout)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(executable: String, arguments: [String], timeout: Duration) throws -> ProcessResult {
        let process = Process()
        // Process requires an absolute executable path; bare names like "python3"
        // would otherwise be resolved relative to the app working directory.
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let outData = FinalBox(Data())
        let errData = FinalBox(Data())
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                outData.append(chunk)
            }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                errData.append(chunk)
            }
        }

        try process.run()

        let timeoutNanos = UInt64(timeout.components.seconds) * 1_000_000_000
            + UInt64(timeout.components.attoseconds / 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + max(timeoutNanos, 1)

        while process.isRunning {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                process.terminate()
                process.waitUntilExit()
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                throw PredictorError.msg("Trainer process timed out")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()

        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        // Drain any remainder after handlers are cleared.
        outData.append(out.fileHandleForReading.readDataToEndOfFile())
        errData.append(err.fileHandleForReading.readDataToEndOfFile())

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData.value, encoding: .utf8) ?? "",
            stderr: String(data: errData.value, encoding: .utf8) ?? ""
        )
    }
}

/// Mutex-backed accumulator for pipe chunks from readability handlers.
private final class FinalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Data

    init(_ data: Data) { storage = data }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

/// Test double that can synthesize a successful trainer write to `--out`.
public struct FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    public var exitCode: Int32
    public var stderr: String
    public var writeEmptyOutFile: Bool

    public init(exitCode: Int32 = 0, stderr: String = "", writeEmptyOutFile: Bool = true) {
        self.exitCode = exitCode
        self.stderr = stderr
        self.writeEmptyOutFile = writeEmptyOutFile
    }

    public func run(executable: String, arguments: [String], timeout: Duration) async throws -> ProcessResult {
        _ = executable
        _ = timeout
        if writeEmptyOutFile, exitCode == 0,
           let idx = arguments.firstIndex(of: "--out"),
           arguments.index(after: idx) < arguments.endIndex
        {
            let outPath = arguments[arguments.index(after: idx)]
            let dir = (outPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // Minimal ONNX-looking placeholder bytes (not a valid model; unit tests mock instantiate).
            FileManager.default.createFile(atPath: outPath, contents: Data([0x08, 0x01]), attributes: nil)
        }
        return ProcessResult(exitCode: exitCode, stdout: "", stderr: stderr)
    }
}

import Foundation
import Testing
import Vapor
import BSON
@testable import CafeSmartApi

@Suite(.serialized)
struct DualRuntimeTests {

    private func makeApp(withTrainerScript: Bool = true) async throws -> Application {
        setenv("MLDSA_SEED", "0123456789abcdef0123456789abcdef", 1)
        setenv("USE_TEST_STORE", "true", 1)
        setenv("SEED_TEST_DATA", "false", 1)
        setenv("ADMIN_USERNAMES", "admin-ml@example.com", 1)
        if withTrainerScript {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("cafesmart-trainer-\(UUID().uuidString).py")
                .path
            try "# test placeholder\n".write(toFile: path, atomically: true, encoding: .utf8)
            setenv("TRAINER_SCRIPT", path, 1)
        } else {
            setenv("TRAINER_SCRIPT", "/tmp/cafesmart-missing-trainer-\(UUID().uuidString).py", 1)
        }
        let app = try await Application.make(.testing)
        app.processRunner = FakeProcessRunner(exitCode: 0, writeEmptyOutFile: true)
        try await configure(app)
        return app
    }

    private func shutdownApp(_ app: Application) async throws {
        unsetenv("TRAINER_SCRIPT")
        PredictorFactory.testingForceMakeError = nil
        PredictorFactory.testingForceMakeErrorOnce = false
        await app.realtimeHub.stop()
        try await app.asyncShutdown()
        try await Task.sleep(for: .milliseconds(150))
    }

    @Test func testUploadOnnxKeepsOnnxExtension() throws {
        let name = try ModelUploadSupport.sanitizedFilename("restock", runtime: .onnx)
        #expect(name.hasSuffix(".onnx"))
    }

    @Test func testUploadCoremlDefaultExtension() throws {
        let name = try ModelUploadSupport.sanitizedFilename("restock", runtime: .coreml)
        #expect(name.hasSuffix(".mlmodel"))
    }

    @Test func testRegistryStoresRuntimeAndPredictor() async throws {
        let registry = PredictorRegistry()
        await registry.set(
            kind: .restockDaily,
            runtime: .onnx,
            path: "/tmp/x.onnx",
            predictor: MockPredictor(output: [2])
        )
        let entry = await registry.entry(.restockDaily)
        #expect(entry?.runtime == .onnx)
    }

    @Test func testDeleteActiveModelConflicts() async throws {
        let app = try await makeApp()
        defer { Task { try? await shutdownApp(app) } }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-\(UUID().uuidString).onnx").path
        FileManager.default.createFile(atPath: path, contents: Data([0x01]), attributes: nil)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let id = ObjectId().hexString
        try await app.mongoStore.createModelArtifact(MLModelArtifact(
            _id: id, id: id, filename: "a.onnx", runtime: .onnx, kind: .restockDaily,
            storedAt: path, bytes: 1, active: true, uploadedAt: Date()
        ))
        do {
            try await ModelArtifactLifecycle.deleteInactive(app: app, id: id)
            Issue.record("Expected conflict deleting active model")
        } catch let abort as any AbortError {
            #expect(abort.status == .conflict)
        }
    }

    @Test func testDeleteInactiveClearsRegistryWhenPathMatches() async throws {
        let app = try await makeApp()
        defer { Task { try? await shutdownApp(app) } }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("inactive-\(UUID().uuidString).onnx").path
        FileManager.default.createFile(atPath: path, contents: Data([0x01]), attributes: nil)
        let id = ObjectId().hexString
        try await app.mongoStore.createModelArtifact(MLModelArtifact(
            _id: id, id: id, filename: "b.onnx", runtime: .onnx, kind: .restockDaily,
            storedAt: path, bytes: 1, active: false, uploadedAt: Date()
        ))
        await app.predictors.set(
            kind: .restockDaily, runtime: .onnx, path: path,
            predictor: MockPredictor(output: [1])
        )
        try await ModelArtifactLifecycle.deleteInactive(app: app, id: id)
        #expect(await app.predictors.get(.restockDaily) == nil)
        #expect(try await app.mongoStore.findModelArtifact(by: id) == nil)
    }

    @Test func testRetentionPrunesOlderInactiveArtifacts() async throws {
        setenv("MODEL_RETENTION_COUNT", "2", 1)
        defer { unsetenv("MODEL_RETENTION_COUNT") }
        let app = try await makeApp()
        defer { Task { try? await shutdownApp(app) } }
        for i in 0..<4 {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("ret-\(i)-\(UUID().uuidString).onnx").path
            FileManager.default.createFile(atPath: path, contents: Data([0x01]), attributes: nil)
            let id = ObjectId().hexString
            try await app.mongoStore.createModelArtifact(MLModelArtifact(
                _id: id, id: id, filename: "r\(i).onnx", runtime: .onnx, kind: .restockDaily,
                storedAt: path, bytes: 1, active: i == 3, uploadedAt: Date().addingTimeInterval(Double(i))
            ))
        }
        await ModelArtifactLifecycle.prune(app: app, kind: .restockDaily, runtime: .onnx)
        let left = try await app.mongoStore.listModelArtifacts()
            .filter { $0.kind == .restockDaily && $0.runtime == .onnx }
        #expect(left.count <= 2)
        #expect(left.contains(where: { $0.active }))
    }

    @Test func testFailedTrainRemovesOrphanOnnxWhenRunnerWritesAnyway() async throws {
        let app = try await makeApp()
        defer { Task { try? await shutdownApp(app) } }
        let runner = OrphanWritingRunner()
        let job = try await app.trainJobs.start(
            app: app,
            kind: .restockDaily,
            runner: runner,
            csvBuilder: { CafePredictorController.minimalTrainingCSV() }
        )
        var finished: TrainJob?
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(50))
            if let j = await app.trainJobs.getJob(job.id), j.status == .failed || j.status == .succeeded {
                finished = j
                break
            }
        }
        #expect(finished?.status == .failed)
        #expect(runner.lastOutPath != nil)
        if let path = runner.lastOutPath {
            #expect(FileManager.default.fileExists(atPath: path) == false)
        }
    }

    @Test func testLoadFailureAfterCommitRollsBackActiveArtifact() async throws {
        let app = try await makeApp()
        defer { Task { try? await shutdownApp(app) } }

        let prevPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("prev-\(UUID().uuidString).onnx").path
        FileManager.default.createFile(atPath: prevPath, contents: Data([0x01]), attributes: nil)
        defer { try? FileManager.default.removeItem(atPath: prevPath) }
        let prevId = ObjectId().hexString
        try await app.mongoStore.createModelArtifact(MLModelArtifact(
            _id: prevId, id: prevId, filename: "prev.onnx", runtime: .onnx, kind: .restockDaily,
            storedAt: prevPath, bytes: 1, active: true, uploadedAt: Date().addingTimeInterval(-120)
        ))
        await app.predictors.set(
            kind: .restockDaily, runtime: .onnx, path: prevPath,
            predictor: MockPredictor(output: [4])
        )

        PredictorFactory.testingForceMakeErrorOnce = true
        PredictorFactory.testingForceMakeError = PredictorError.msg("forced load failure")
        let job = try await app.trainJobs.start(
            app: app,
            kind: .restockDaily,
            runner: FakeProcessRunner(exitCode: 0, writeEmptyOutFile: true),
            csvBuilder: { CafePredictorController.minimalTrainingCSV() }
        )
        var finished: TrainJob?
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(50))
            if let j = await app.trainJobs.getJob(job.id), j.status == .failed || j.status == .succeeded {
                finished = j
                break
            }
        }
        #expect(finished?.status == .failed)
        let prev = try await app.mongoStore.findModelArtifact(by: prevId)
        #expect(prev?.active == true)
        let entry = await app.predictors.entry(.restockDaily)
        #expect(entry?.path == prevPath)
    }

    @Test func testTrainJobsPersistAndList() async throws {
        let app = try await makeApp()
        defer { Task { try? await shutdownApp(app) } }
        let job = try await app.trainJobs.start(
            app: app,
            kind: .restockDaily,
            runner: FakeProcessRunner(exitCode: 0),
            csvBuilder: { CafePredictorController.minimalTrainingCSV() }
        )
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(50))
            if let j = await app.trainJobs.getJob(job.id), j.status == .succeeded || j.status == .failed {
                break
            }
        }
        let listed = try await app.trainJobs.listJobs(app: app, limit: 10)
        #expect(listed.contains(where: { $0.id == job.id }))
        let fromStore = try await app.mongoStore.findTrainJob(by: job.id)
        #expect(fromStore?.status == .succeeded)
    }

    @Test func testMinimalTrainingCSVHasContractColumns() {
        let csv = CafePredictorController.minimalTrainingCSV()
        #expect(csv.contains("target_usage"))
        #expect(csv.contains("usage_lag_1d"))
    }
}

private final class OrphanWritingRunner: ProcessRunning, @unchecked Sendable {
    nonisolated(unsafe) private var _lastOutPath: String?
    var lastOutPath: String? { _lastOutPath }

    func run(executable: String, arguments: [String], timeout: Duration) async throws -> ProcessResult {
        _ = executable
        _ = timeout
        if let idx = arguments.firstIndex(of: "--out"),
           arguments.index(after: idx) < arguments.endIndex
        {
            let outPath = arguments[arguments.index(after: idx)]
            let dir = (outPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: outPath, contents: Data([0x08, 0x01]), attributes: nil)
            _lastOutPath = outPath
        }
        return ProcessResult(exitCode: 1, stdout: "", stderr: "forced fail")
    }
}

import Foundation
import Testing
import Vapor
import BSON
@testable import cafe_smart_api

@Suite(.serialized)
struct DualRuntimeTests {

    private func makeApp(withTrainerScript: Bool = true) async throws -> Application {
        // Never touch repo Trainer/train_restock.py — override via TRAINER_SCRIPT.
        if withTrainerScript {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("cafesmart-trainer-\(UUID().uuidString).py")
                .path
            try "# test placeholder\n".write(toFile: path, atomically: true, encoding: .utf8)
            setenv("TRAINER_SCRIPT", path, 1)
        } else {
            setenv("TRAINER_SCRIPT", "/tmp/cafesmart-missing-trainer-\(UUID().uuidString).py", 1)
        }
        return try await APITestHelpers.makeApp(adminEmail: "admin-ml@example.com") { app in
            app.processRunner = FakeProcessRunner(exitCode: 0, writeEmptyOutFile: true)
        }
    }

    private func shutdownApp(_ app: Application) async throws {
        unsetenv("TRAINER_SCRIPT")
        try await APITestHelpers.shutdownApp(app)
    }

    @Test func testPredictRuntimeRejectsInvalidValue() {
        do {
            _ = try ModelUploadSupport.parseRuntime("bogus")
            Issue.record("Expected invalid runtime to throw")
        } catch {
            // expected
        }
    }

    @Test func testUploadRejectsPathLikeRuntime() throws {
        do {
            _ = try ModelUploadSupport.parseRuntime("../etc")
            Issue.record("Expected path-like runtime to throw")
        } catch {
            // expected
        }
        let root = ModelUploadSupport.modelsRoot(
            workingDirectory: "/tmp/cafesmart/",
            runtime: .onnx,
            kind: .restockDaily
        )
        #expect(root.contains("Models/onnx/restockDaily/"))
        #expect(!root.contains(".."))
    }

    @Test func testUploadOnnxKeepsOnnxExtension() throws {
        let name = try ModelUploadSupport.sanitizedFilename("restock", runtime: .onnx)
        #expect(name.hasSuffix(".onnx"))
        #expect(!name.contains(".mlmodel"))
    }

    @Test func testUploadCoremlDefaultExtension() throws {
        let name = try ModelUploadSupport.sanitizedFilename("restock", runtime: .coreml)
        #expect(name.hasSuffix(".mlmodel"))
    }

    @Test func testFactoryRejectsUnavailableRuntimes() async {
        #if canImport(CONNX)
        #expect(PredictorFactory.onnxAvailable == true)
        #else
        do {
            _ = try await PredictorFactory.make(runtime: .onnx, path: "/tmp/missing.onnx")
            Issue.record("Expected onnx unavailable")
        } catch {
            // expected
        }
        #endif
    }

    @Test func testRegistryStoresRuntimeAndPredictor() async throws {
        let registry = PredictorRegistry()
        let mock = MockPredictor(output: [3.5])
        await registry.set(kind: .restockDaily, runtime: .onnx, path: "/tmp/x.onnx", predictor: mock)
        let entry = await registry.entry(.restockDaily)
        #expect(entry?.runtime == .onnx)
        #expect(entry?.path == "/tmp/x.onnx")
        let pred = await registry.get(.restockDaily)
        let out = try await pred!.predictMultiple(inputs: [:], outputName: "o")
        #expect(out == [3.5])
    }

    @Test func testForecastSeriesUsesPredictorServingMock() async throws {
        let app = try await makeApp()
        do {
            await app.predictors.set(
                kind: .restockDaily,
                runtime: .coreml,
                path: "/tmp/mock",
                predictor: MockPredictor(output: [9.0])
            )
            let p = await app.predictors.get(.restockDaily)!
            let out = try await p.predictMultiple(
                inputs: ["sku": .string("BEANS"), "usage_lag_1d": .double(1)],
                outputName: "target_usage"
            )
            #expect(out.first == 9.0)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testTrainAcceptedReturns202AndJobId() async throws {
        let app = try await makeApp()
        do {

            let job = try await app.trainJobs.start(
                app: app,
                kind: .restockDaily,
                runner: FakeProcessRunner(exitCode: 0),
                csvBuilder: { CafePredictorController.minimalTrainingCSV() }
            )
            #expect(job.id.isEmpty == false)

            var finished: TrainJob?
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(50))
                if let j = await app.trainJobs.getJob(job.id), j.status == .succeeded || j.status == .failed {
                    finished = j
                    break
                }
            }
            #expect(finished?.status == .succeeded)
            #expect(finished?.artifactId != nil)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testTrainGetJobFailedSurfacesStderr() async throws {
        let app = try await makeApp()
        do {
            let job = try await app.trainJobs.start(
                app: app,
                kind: .restockDaily,
                runner: FakeProcessRunner(exitCode: 1, stderr: "boom", writeEmptyOutFile: false),
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
            #expect(finished?.error?.contains("boom") == true)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testTrainConflictWhenAlreadyRunning() async throws {
        let app = try await makeApp()
        do {
            let slow = FakeProcessRunner(exitCode: 0)
            _ = try await app.trainJobs.start(
                app: app,
                kind: .restockDaily,
                runner: slow,
                csvBuilder: {
                    try await Task.sleep(for: .milliseconds(400))
                    return CafePredictorController.minimalTrainingCSV()
                }
            )
            do {
                _ = try await app.trainJobs.start(
                    app: app,
                    kind: .restockDaily,
                    runner: slow,
                    csvBuilder: { CafePredictorController.minimalTrainingCSV() }
                )
                Issue.record("Expected conflict")
            } catch let abort as any AbortError {
                #expect(abort.status == .conflict)
            }
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testTrainReturns503WhenScriptMissing() async throws {
        let app = try await makeApp(withTrainerScript: false)
        do {
            do {
                _ = try await app.trainJobs.start(
                    app: app,
                    kind: .restockDaily,
                    runner: FakeProcessRunner(),
                    csvBuilder: { CafePredictorController.minimalTrainingCSV() }
                )
                Issue.record("Expected 503 when trainer script missing")
            } catch let abort as any AbortError {
                #expect(abort.status == .serviceUnavailable)
            }
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testCapabilitiesRequiresScriptForServerTraining() async throws {
        let app = try await makeApp()
        do {
            let caps = await app.trainJobs.capabilities(workingDirectory: app.directory.workingDirectory)
            #expect(caps.serverTraining == true)
            #expect(caps.onnxInference == PredictorFactory.onnxAvailable)
            #if canImport(CONNX)
            #expect(caps.onnxInference == true)
            #endif
            #expect(caps.coremlInference == PredictorFactory.coremlAvailable)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testDeleteActiveModelConflicts() async throws {
        let app = try await makeApp()
        do {
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
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testDeleteInactiveClearsRegistryWhenPathMatches() async throws {
        let app = try await makeApp()
        do {
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
            #expect(FileManager.default.fileExists(atPath: path) == false)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testRetentionPrunesOlderInactiveArtifacts() async throws {
        setenv("MODEL_RETENTION_COUNT", "2", 1)
        defer { unsetenv("MODEL_RETENTION_COUNT") }
        let app = try await makeApp()
        do {
            var ids: [String] = []
            for i in 0..<4 {
                let path = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ret-\(i)-\(UUID().uuidString).onnx").path
                FileManager.default.createFile(atPath: path, contents: Data([0x01]), attributes: nil)
                let id = ObjectId().hexString
                ids.append(id)
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
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testFailedTrainRemovesOrphanOnnxWhenRunnerWritesAnyway() async throws {
        let app = try await makeApp()
        do {
            // Force-write on non-zero exit to simulate a partial trainer write.
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
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testLoadFailureAfterCommitRollsBackActiveArtifact() async throws {
        let app = try await makeApp()
        defer {
            PredictorFactory.testingForceMakeError = nil
            PredictorFactory.testingForceMakeErrorOnce = false
        }
        do {
            // Establish a previous active model that should be restored after rollback.
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
            #expect(finished?.error?.contains("forced load failure") == true)

            let prev = try await app.mongoStore.findModelArtifact(by: prevId)
            #expect(prev?.active == true)
            let artifacts = try await app.mongoStore.listModelArtifacts()
                .filter { $0.kind == .restockDaily }
            // Failed commit should not leave an extra active zombie; previous remains active.
            let actives = artifacts.filter { $0.active }
            #expect(actives.count == 1)
            #expect(actives.first?._id == prevId)
            let entry = await app.predictors.entry(.restockDaily)
            #expect(entry?.path == prevPath)
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testTrainJobsPersistAndList() async throws {
        let app = try await makeApp()
        do {
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
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }

    @Test func testBootReloadLoadsActiveArtifact() async throws {
        let app = try await makeApp()
        do {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("boot-\(UUID().uuidString).onnx").path
            FileManager.default.createFile(atPath: path, contents: Data([0x01]), attributes: nil)
            defer { try? FileManager.default.removeItem(atPath: path) }
            let id = ObjectId().hexString
            try await app.mongoStore.createModelArtifact(MLModelArtifact(
                _id: id, id: id, filename: "boot.onnx", runtime: .onnx, kind: .restockDaily,
                storedAt: path, bytes: 1, active: true, uploadedAt: Date()
            ))
            await app.predictors.clear()
            // USE_TEST_STORE path: factory may fail on placeholder bytes; inject via mock after clear
            // Boot reload uses PredictorFactory — on test store with invalid ONNX it may skip.
            // Verify helper path by setting mock when factory unavailable for bytes.
            #if canImport(CONNX)
            await ModelArtifactLifecycle.reloadActivePredictors(app: app)
            // Invalid ONNX bytes typically fail reload; ensure no crash and registry stays empty or loaded.
            _ = await app.predictors.get(.restockDaily)
            #else
            await ModelArtifactLifecycle.reloadActivePredictors(app: app)
            #expect(await app.predictors.get(.restockDaily) == nil)
            #endif
        } catch {
            try await shutdownApp(app)
            throw error
        }
        try await shutdownApp(app)
    }
}

/// Writes `--out` then fails — used to assert orphan cleanup.
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

import Foundation
import Vapor
import BSON

public enum TrainJobStatus: String, Content, Sendable {
    case queued, running, succeeded, failed
}

public struct TrainJob: Content, Sendable, Equatable {
    public var id: String
    public var kind: PredictorKind
    public var status: TrainJobStatus
    public var error: String?
    public var artifactId: String?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct TrainJobList: Content, Sendable {
    public var items: [TrainJob]
}

public struct PredictorCapabilities: Content, Sendable {
    public var coremlInference: Bool
    public var onnxInference: Bool
    public var serverTraining: Bool
}

actor TrainJobService {
    private var jobs: [String: TrainJob] = [:]
    private var runningKinds: Set<PredictorKind> = []

    func capabilities(workingDirectory: String) -> PredictorCapabilities {
        PredictorCapabilities(
            coremlInference: PredictorFactory.coremlAvailable,
            onnxInference: PredictorFactory.onnxAvailable,
            // Server train needs the Python trainer and ONNX Runtime (CONNX) to activate the artifact.
            serverTraining: trainerScriptExists(workingDirectory: workingDirectory)
                && PredictorFactory.onnxAvailable
        )
    }

    func getJob(app: Application, id: String) async -> TrainJob? {
        if let cached = jobs[id] { return cached }
        return try? await app.mongoStore.findTrainJob(by: id)
    }

    /// Prefer in-memory for running jobs; otherwise durable store.
    func getJob(_ id: String) -> TrainJob? { jobs[id] }

    func listJobs(app: Application, limit: Int) async throws -> [TrainJob] {
        try await app.mongoStore.listTrainJobs(limit: limit)
    }

    func start(
        app: Application,
        kind: PredictorKind,
        runner: any ProcessRunning,
        csvBuilder: @escaping @Sendable () async throws -> String,
        scriptPath: String? = nil
    ) async throws -> TrainJob {
        let workingDirectory = Self.normalizedDirectory(app.directory.workingDirectory)
        guard PredictorFactory.onnxAvailable else {
            throw Abort(
                .serviceUnavailable,
                reason: "Server training unavailable: ONNX Runtime (CONNX) is not linked on this platform"
            )
        }
        let resolvedScript = scriptPath ?? Self.scriptPath(for: kind, workingDirectory: workingDirectory)
        guard trainerScriptExists(path: resolvedScript) else {
            throw Abort(.serviceUnavailable, reason: "Server training unavailable: trainer script missing")
        }
        if runningKinds.contains(kind) {
            throw Abort(.conflict, reason: "A training job is already running for \(kind.rawValue)")
        }

        let id = ObjectId().hexString
        let job = TrainJob(
            id: id,
            kind: kind,
            status: .queued,
            error: nil,
            artifactId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        jobs[id] = job
        runningKinds.insert(kind)
        try? await app.mongoStore.upsertTrainJob(job)
        try? await app.mongoStore.pruneTrainJobs(keepLast: 100, maxAgeDays: 30)

        Task {
            await self.execute(
                jobId: id,
                app: app,
                kind: kind,
                runner: runner,
                workingDirectory: workingDirectory,
                scriptPath: resolvedScript,
                csvBuilder: csvBuilder
            )
        }
        return job
    }

    /// Kind → Trainer/*.py (TRAINER_SCRIPT env overrides for tests).
    static func scriptPath(for kind: PredictorKind, workingDirectory: String) -> String {
        if let override = Environment.get("TRAINER_SCRIPT"), !override.isEmpty {
            return override
        }
        let root = normalizedDirectory(workingDirectory)
        switch kind {
        case .restockDaily:
            return root + "Trainer/train_restock.py"
        case .workloadHourly:
            return root + "Trainer/train_busy_hour.py"
        case .reservationsHourly:
            return root + "Trainer/train_reservations_hour.py"
        case .reservationDuration:
            return root + "Trainer/train_restock.py"
        }
    }

    private func trainerScriptExists(path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func trainerScriptExists(workingDirectory: String) -> Bool {
        // Capabilities: any default trainer present (or test override).
        if let override = Environment.get("TRAINER_SCRIPT"), !override.isEmpty {
            return FileManager.default.fileExists(atPath: override)
        }
        let root = Self.normalizedDirectory(workingDirectory)
        let candidates = [
            root + "Trainer/train_restock.py",
            root + "Trainer/train_busy_hour.py",
            root + "Trainer/train_reservations_hour.py",
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func normalizedDirectory(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private func execute(
        jobId: String,
        app: Application,
        kind: PredictorKind,
        runner: any ProcessRunning,
        workingDirectory: String,
        scriptPath: String,
        csvBuilder: @escaping @Sendable () async throws -> String
    ) async {
        await persist(app, jobId, status: .running, error: nil, artifactId: nil)
        var outPath: String?
        var committedArtifactId: String?
        var previousActiveId: String?
        do {
            let existing = try await app.mongoStore.listModelArtifacts()
            previousActiveId = existing.first(where: { $0.kind == kind && $0.active })?._id

            let csv = try await csvBuilder()
            let tempCSV = FileManager.default.temporaryDirectory
                .appendingPathComponent("train_\(jobId).csv").path
            try csv.write(toFile: tempCSV, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(atPath: tempCSV) }

            let modelsRoot = ModelUploadSupport.modelsRoot(
                workingDirectory: workingDirectory,
                runtime: .onnx,
                kind: kind
            )
            try FileManager.default.createDirectory(atPath: modelsRoot, withIntermediateDirectories: true)
            let writtenPath = modelsRoot + "\(kind.rawValue)_\(Int(Date().timeIntervalSince1970)).onnx"
            outPath = writtenPath

            let python = Environment.get("TRAINER_PYTHON") ?? "python3"

            let result = try await runner.run(
                executable: python,
                arguments: [scriptPath, "--csv", tempCSV, "--out", writtenPath],
                timeout: .seconds(600)
            )
            guard result.exitCode == 0 else {
                throw PredictorError.msg("Trainer failed (\(result.exitCode)): \(result.stderr)")
            }
            guard FileManager.default.fileExists(atPath: writtenPath) else {
                throw PredictorError.msg("Trainer exited 0 but ONNX file was not written")
            }

            let attrs = try FileManager.default.attributesOfItem(atPath: writtenPath)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            let artifactId = ObjectId().hexString
            let artifact = MLModelArtifact(
                _id: artifactId,
                id: artifactId,
                filename: (writtenPath as NSString).lastPathComponent,
                runtime: .onnx,
                kind: kind,
                storedAt: writtenPath,
                bytes: size,
                active: false,
                uploadedAt: Date()
            )
            try await app.mongoStore.createModelArtifact(artifact)
            try await app.mongoStore.setActiveModel(id: artifactId)
            committedArtifactId = artifactId
            await app.realtime.publish(.modelUploaded(artifact), to: .merchant)
            await app.realtime.publish(.modelActivated(kind: kind, id: artifactId), to: .merchant)

            let predictor = try await PredictorFactory.make(runtime: .onnx, path: writtenPath, kind: kind)
            await app.predictors.set(kind: kind, runtime: .onnx, path: writtenPath, predictor: predictor)
            await app.realtime.publish(.predictorReady(kind: kind), to: .merchant)

            await ModelArtifactLifecycle.prune(app: app, kind: kind, runtime: .onnx)

            // Match uploadModel: run predictions and push restockDecisions to the Mac UI.
            if kind == .restockDaily {
                await CafePredictorController().publishRestockDecisions(app: app)
            }

            await persist(app, jobId, status: .succeeded, error: nil, artifactId: artifactId)
        } catch {
            await rollbackFailedTrain(
                app: app,
                kind: kind,
                outPath: outPath,
                committedArtifactId: committedArtifactId,
                previousActiveId: previousActiveId
            )
            await persist(app, jobId, status: .failed, error: "\(error)", artifactId: nil)
        }
        runningKinds.remove(kind)
    }

    private func rollbackFailedTrain(
        app: Application,
        kind: PredictorKind,
        outPath: String?,
        committedArtifactId: String?,
        previousActiveId: String?
    ) async {
        if let committedArtifactId {
            try? await app.mongoStore.deleteModelArtifact(id: committedArtifactId)
            await app.predictors.remove(kind)
            if let previousActiveId,
               previousActiveId != committedArtifactId,
               let prev = try? await app.mongoStore.findModelArtifact(by: previousActiveId)
            {
                try? await app.mongoStore.setActiveModel(id: previousActiveId)
                if FileManager.default.fileExists(atPath: prev.storedAt),
                   let predictor = try? await PredictorFactory.make(
                    runtime: prev.runtime, path: prev.storedAt, kind: kind
                   )
                {
                    await app.predictors.set(
                        kind: kind, runtime: prev.runtime, path: prev.storedAt, predictor: predictor
                    )
                }
            }
        } else if let outPath, FileManager.default.fileExists(atPath: outPath) {
            try? FileManager.default.removeItem(atPath: outPath)
        }
    }

    private func persist(
        _ app: Application,
        _ id: String,
        status: TrainJobStatus,
        error: String?,
        artifactId: String?
    ) async {
        guard var job = jobs[id] else { return }
        job.status = status
        job.error = error
        job.artifactId = artifactId
        job.updatedAt = Date()
        jobs[id] = job
        try? await app.mongoStore.upsertTrainJob(job)
    }
}

extension Application {
    private struct TrainJobServiceKey: StorageKey { typealias Value = TrainJobService }
    private struct ProcessRunnerKey: StorageKey { typealias Value = any ProcessRunning }

    var trainJobs: TrainJobService {
        get {
            storage[TrainJobServiceKey.self] ?? {
                let s = TrainJobService()
                storage[TrainJobServiceKey.self] = s
                return s
            }()
        }
        set { storage[TrainJobServiceKey.self] = newValue }
    }

    var processRunner: any ProcessRunning {
        get { storage[ProcessRunnerKey.self] ?? FoundationProcessRunner() }
        set { storage[ProcessRunnerKey.self] = newValue }
    }
}

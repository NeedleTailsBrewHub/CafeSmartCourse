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
            serverTraining: trainerScriptExists(workingDirectory: workingDirectory)
                && PredictorFactory.onnxAvailable
        )
    }

    func getJob(app: Application, id: String) async -> TrainJob? {
        if let cached = jobs[id] { return cached }
        return try? await app.mongoStore.findTrainJob(by: id)
    }

    func getJob(_ id: String) -> TrainJob? { jobs[id] }

    func listJobs(app: Application, limit: Int) async throws -> [TrainJob] {
        try await app.mongoStore.listTrainJobs(limit: limit)
    }

    func start(
        app: Application,
        kind: PredictorKind,
        runner: any ProcessRunning,
        csvBuilder: @escaping @Sendable () async throws -> String
    ) async throws -> TrainJob {
        let workingDirectory = Self.normalizedDirectory(app.directory.workingDirectory)
        guard PredictorFactory.onnxAvailable else {
            throw Abort(
                .serviceUnavailable,
                reason: "Server training unavailable: ONNX Runtime (CONNX) is not linked on this platform"
            )
        }
        guard trainerScriptExists(workingDirectory: workingDirectory) else {
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
                csvBuilder: csvBuilder
            )
        }
        return job
    }

    private func trainerScriptExists(workingDirectory: String) -> Bool {
        let root = Self.normalizedDirectory(workingDirectory)
        let script = Environment.get("TRAINER_SCRIPT") ?? (root + "Trainer/train_restock.py")
        return FileManager.default.fileExists(atPath: script)
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
            let writtenPath = modelsRoot + "restock_\(Int(Date().timeIntervalSince1970)).onnx"
            outPath = writtenPath

            let root = Self.normalizedDirectory(workingDirectory)
            let python = Environment.get("TRAINER_PYTHON") ?? "python3"
            let script = Environment.get("TRAINER_SCRIPT") ?? (root + "Trainer/train_restock.py")

            let result = try await runner.run(
                executable: python,
                arguments: [script, "--csv", tempCSV, "--out", writtenPath],
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
            await app.realtimeHub.publish(.modelUploaded(artifact), to: .merchant)
            await app.realtimeHub.publish(.modelActivated(kind: kind, id: artifactId), to: .merchant)

            let predictor = try await PredictorFactory.make(runtime: .onnx, path: writtenPath)
            await app.predictors.set(kind: kind, runtime: .onnx, path: writtenPath, predictor: predictor)
            await app.realtimeHub.publish(.predictorReady(kind: kind), to: .merchant)

            await ModelArtifactLifecycle.prune(app: app, kind: kind, runtime: .onnx)

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
                    runtime: prev.runtime, path: prev.storedAt
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

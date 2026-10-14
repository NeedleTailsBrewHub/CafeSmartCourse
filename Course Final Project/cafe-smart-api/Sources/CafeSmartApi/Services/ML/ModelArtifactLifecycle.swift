import Foundation
import Vapor

/// Shared model-artifact retention, delete, and boot-time predictor reload.
enum ModelArtifactLifecycle {
    static var retentionCount: Int {
        let raw = Environment.get("MODEL_RETENTION_COUNT") ?? "5"
        return max(1, Int(raw) ?? 5)
    }

    /// Load each kind's active artifact into the in-memory registry (best-effort).
    static func reloadActivePredictors(app: Application) async {
        do {
            let artifacts = try await app.mongoStore.listModelArtifacts()
            let active = artifacts.filter(\.active)
            for artifact in active {
                guard FileManager.default.fileExists(atPath: artifact.storedAt) else {
                    app.logger.warning(
                        "Active model missing on disk; skip reload kind=\(artifact.kind.rawValue) path=\(artifact.storedAt)"
                    )
                    continue
                }
                do {
                    let predictor = try await PredictorFactory.make(
                        runtime: artifact.runtime,
                        path: artifact.storedAt
                    )
                    await app.predictors.set(
                        kind: artifact.kind,
                        runtime: artifact.runtime,
                        path: artifact.storedAt,
                        predictor: predictor
                    )
                    app.logger.info(
                        "Reloaded predictor kind=\(artifact.kind.rawValue) runtime=\(artifact.runtime.rawValue) id=\(artifact._id)"
                    )
                } catch {
                    app.logger.warning(
                        "Failed to reload predictor kind=\(artifact.kind.rawValue): \(error)"
                    )
                }
            }
        } catch {
            app.logger.warning("Boot predictor reload failed: \(error)")
        }
    }

    /// Delete an inactive artifact from disk + store and clear registry if it pointed at that path.
    static func deleteInactive(app: Application, id: String) async throws {
        guard let artifact = try await app.mongoStore.findModelArtifact(by: id) else {
            throw Abort(.notFound, reason: "Model artifact not found")
        }
        if artifact.active {
            throw Abort(
                .conflict,
                reason: "Cannot delete the active model; activate another model first"
            )
        }
        if let entry = await app.predictors.entry(artifact.kind), entry.path == artifact.storedAt {
            await app.predictors.remove(artifact.kind)
        }
        try await app.mongoStore.deleteModelArtifact(id: artifact._id)
        await app.realtimeHub.publish(.modelDeleted(id: artifact._id), to: .merchant)
    }

    /// Keep active + newest inactive artifacts up to `retentionCount` per kind+runtime.
    static func prune(app: Application, kind: PredictorKind, runtime: PredictRuntime) async {
        let limit = retentionCount
        do {
            let matching = try await app.mongoStore.listModelArtifacts()
                .filter { $0.kind == kind && $0.runtime == runtime }
                .sorted { $0.uploadedAt > $1.uploadedAt }

            var keep = Set<String>()
            if let active = matching.first(where: \.active) {
                keep.insert(active._id)
            }
            for art in matching where keep.count < limit {
                keep.insert(art._id)
            }

            for art in matching where !keep.contains(art._id) {
                if art.active { continue }
                if let entry = await app.predictors.entry(art.kind), entry.path == art.storedAt {
                    await app.predictors.remove(art.kind)
                }
                try? await app.mongoStore.deleteModelArtifact(id: art._id)
                await app.realtimeHub.publish(.modelDeleted(id: art._id), to: .merchant)
            }
        } catch {
            app.logger.warning("Model retention prune failed: \(error)")
        }
    }
}

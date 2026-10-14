//
//  ModelsAdminViewModel.swift
//  CafeSmartDev
//

import Foundation
import Observation

@MainActor
@Observable
final class ModelsAdminViewModel {
    static let shared = ModelsAdminViewModel()

    var models: [MLModelArtifact] = []
    var jobs: [TrainJobDTO] = []
    var isTraining = false
    var trainingStatusText: String?
    var lastError: String?
    var isLoading = false
    var serverTrainingAvailable = false

    private init() {}

    var activeRestock: MLModelArtifact? {
        models.first(where: { $0.kind == .restockDaily && $0.active })
    }

    func artifactId(_ artifact: MLModelArtifact) -> String {
        artifact.id ?? artifact._id ?? ""
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        var errors: [String] = []
        do {
            let listed = try await AIService.shared.listModels()
            models = listed.sorted { ($0.uploadedAt ?? .distantPast) > ($1.uploadedAt ?? .distantPast) }
        } catch {
            errors.append("Models: \(error.localizedDescription)")
        }
        do {
            jobs = try await AIService.shared.listTrainJobs()
        } catch {
            errors.append("Jobs: \(error.localizedDescription)")
        }
        do {
            serverTrainingAvailable = try await AIService.shared.fetchCapabilities().serverTraining
        } catch {
            errors.append("Capabilities: \(error.localizedDescription)")
        }
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    @discardableResult
    func train(location: TrainingLocation) async throws -> String {
        guard !isTraining else {
            throw URLError(.cannotLoadFromNetwork, userInfo: [NSLocalizedDescriptionKey: "A training job is already in progress"])
        }
        isTraining = true
        trainingStatusText = location == .server ? "Queued…" : "Training locally…"
        lastError = nil
        defer {
            isTraining = false
            trainingStatusText = nil
        }
        do {
            let message: String
            switch location {
            case .server:
                message = try await AIService.shared.trainRestockOnServer { [weak self] job in
                    Task { @MainActor in
                        self?.trainingStatusText = job.status.capitalized
                    }
                }
            case .local:
                #if os(macOS) && canImport(CoreML)
                message = try await MLService.train(location: .local)
                #else
                throw URLError(
                    .unsupportedURL,
                    userInfo: [NSLocalizedDescriptionKey: "Local Create ML training is only available on Mac"])
                #endif
            }
            await refresh()
            return message
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func activate(id: String) async {
        do {
            try await AIService.shared.activateModel(id: id)
            await refresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(id: String) async {
        do {
            try await AIService.shared.deleteModel(id: id)
            await refresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

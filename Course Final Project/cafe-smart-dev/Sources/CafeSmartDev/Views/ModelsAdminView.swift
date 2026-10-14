//
//  ModelsAdminView.swift
//  CafeSmartDev
//

#if os(macOS)
import SwiftUI

struct ModelsAdminView: View {
    @Environment(AppNotificationCenter.self) private var appNotificationCenter
    @Bindable private var viewModel = ModelsAdminViewModel.shared
    @AppStorage("trainingLocation") private var trainingLocationRaw: String = "local"
    @State private var pendingDeleteId: String?

    private var trainingLocation: TrainingLocation {
        TrainingLocation(rawValue: trainingLocationRaw) ?? .local
    }

    var body: some View {
        ScreenCanvas {
            if let err = viewModel.lastError, !err.isEmpty {
                ErrorBanner(message: err)
            }

            PanelSection(title: "Active predictor", subtitle: "Currently loaded restock model") {
                if let active = viewModel.activeRestock {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        LabeledContent("Kind", value: active.kind.rawValue)
                        LabeledContent("Runtime", value: active.runtime?.rawValue ?? "—")
                        LabeledContent("Filename", value: active.filename ?? "—")
                        LabeledContent("ID", value: viewModel.artifactId(active))
                    }
                } else {
                    Text("No active restockDaily model")
                        .foregroundStyle(.secondary)
                }
            }

            PanelSection(title: "Train", subtitle: "Create a new model artifact") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Picker("Location", selection: $trainingLocationRaw) {
                        Text("On this Mac (Create ML → CoreML)").tag("local")
                        Text("On API server (Python → ONNX)").tag("server")
                    }
                    .pickerStyle(.radioGroup)

                    HStack {
                        Button {
                            Task {
                                do {
                                    let message = try await viewModel.train(location: trainingLocation)
                                    appNotificationCenter.show(message, iconSystemName: "checkmark.circle.fill", duration: 3.0)
                                } catch {
                                    appNotificationCenter.show(
                                        "Training failed: \(error.localizedDescription)",
                                        iconSystemName: "xmark.octagon.fill",
                                        duration: 4.0
                                    )
                                }
                            }
                        } label: {
                            if viewModel.isTraining {
                                ProgressView()
                                    .controlSize(.small)
                                Text(viewModel.trainingStatusText ?? "Training…")
                            } else {
                                Label("Train Now", systemImage: "bolt.badge.a.fill")
                            }
                        }
                        .disabled(
                            viewModel.isTraining
                                || (trainingLocation == .server && !viewModel.serverTrainingAvailable)
                        )

                        Button("Refresh") {
                            Task { await viewModel.refresh() }
                        }
                        .disabled(viewModel.isTraining || viewModel.isLoading)
                    }
                    if trainingLocation == .server && !viewModel.serverTrainingAvailable {
                        Text("Server training unavailable (check trainer + ONNX on API).")
                            .font(AppFont.footnote())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PanelSection(title: "Artifacts", subtitle: "Activate or retire models") {
                if viewModel.isLoading && viewModel.models.isEmpty {
                    ProgressView()
                } else if viewModel.models.isEmpty {
                    Text("No model artifacts yet")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.models, id: \.stableId) { artifact in
                            HStack(alignment: .top, spacing: AppSpacing.md) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: AppSpacing.sm) {
                                        Text(artifact.filename ?? "model")
                                            .font(AppFont.headline())
                                        if artifact.active {
                                            StatusChip(text: "Active", tone: .success)
                                        }
                                    }
                                    Text("\(artifact.runtime?.rawValue ?? "—") · \(artifact.kind.rawValue) · \(artifact.bytes.map(String.init) ?? "—") bytes")
                                        .font(AppFont.caption())
                                        .foregroundStyle(.secondary)
                                    if let date = artifact.uploadedAt {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(AppFont.caption())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Activate") {
                                    Task { await viewModel.activate(id: viewModel.artifactId(artifact)) }
                                }
                                .disabled(artifact.active || viewModel.isTraining || viewModel.artifactId(artifact).isEmpty)
                                Button("Delete", role: .destructive) {
                                    pendingDeleteId = viewModel.artifactId(artifact)
                                }
                                .disabled(artifact.active || viewModel.isTraining || viewModel.artifactId(artifact).isEmpty)
                            }
                            .padding(.vertical, 6)
                            if artifact.stableId != viewModel.models.last?.stableId {
                                Divider()
                            }
                        }
                    }
                }
            }

            PanelSection(title: "Job history", subtitle: "Recent server training runs") {
                if viewModel.jobs.isEmpty {
                    Text("No train jobs recorded")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.jobs, id: \.id) { job in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.id)
                                        .font(AppFont.caption())
                                        .lineLimit(1)
                                    if let err = job.error, !err.isEmpty {
                                        Text(err)
                                            .font(AppFont.caption())
                                            .foregroundStyle(.red)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                StatusChip(text: job.status, tone: .neutral)
                                if let artifactId = job.artifactId {
                                    Text(artifactId.prefix(8) + "…")
                                        .font(AppFont.caption())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            if job.id != viewModel.jobs.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog(
            "Delete this model artifact?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId {
                    Task { await viewModel.delete(id: id) }
                }
                pendingDeleteId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteId = nil
            }
        }
    }
}

private extension MLModelArtifact {
    var stableId: String { id ?? _id ?? filename ?? UUID().uuidString }
}
#endif

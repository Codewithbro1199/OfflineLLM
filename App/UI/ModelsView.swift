import SwiftUI

struct ModelsView: View {
    @Environment(AppModel.self) private var app
    @Environment(ChatController.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: ModelInfo?

    var body: some View {
        List {
            Section {
                ForEach(ModelCatalog.all) { model in
                    ModelRow(model: model, isSelected: app.selectedModelID == model.id,
                             onSelect: { if !chat.isGenerating { app.select(model) } },
                             onDelete: { pendingDelete = model })
                }
            } footer: {
                Text("Models download once over Wi-Fi or cellular, then run fully offline. Free space: \(ByteCountFormatter.string(fromByteCount: app.store.freeDiskBytes, countStyle: .file)).")
            }
            Section {
                LabeledContent("Status", value: statusText)
                if case .ready = app.engineState {
                    Button("Unload model to free memory") {
                        Task { await app.releaseMemory() }
                    }
                    .disabled(chat.isGenerating)
                }
            } footer: {
                Text("Qwen3.5 models by Alibaba's Qwen team, quantized by bartowski. Apache-2.0 license.")
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "model")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let model = pendingDelete { Task { await app.delete(model) } }
                pendingDelete = nil
            }
        } message: {
            Text("You can download it again later.")
        }
    }

    private var statusText: String {
        switch app.engineState {
        case .noModel: return "No model installed"
        case .idle: return "Loads on your next message"
        case .loading: return "Loading…"
        case .ready: return "Loaded in memory"
        case .failed(let message): return message
        }
    }
}

struct ModelRow: View {
    @Environment(AppModel.self) private var app
    let model: ModelInfo
    let isSelected: Bool
    var onSelect: () -> Void = {}
    var onDelete: (() -> Void)?

    private var state: ModelInstallState { app.store.state(for: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name).font(.headline)
                        if model.id == ModelCatalog.defaultModelID {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(model.tagline).font(.subheadline).foregroundStyle(.secondary)
                    Text(model.sizeLabel).font(.caption).foregroundStyle(.tertiary)
                    if !app.store.deviceCanRun(model) {
                        Label("May be too large for this iPhone's memory", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                trailing
            }
            switch state {
            case .downloading(let progress, let written):
                ProgressView(value: progress)
                Text("\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) of \(model.sizeLabel)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            case .verifying:
                ProgressView().progressViewStyle(.linear)
                Text("Checking file integrity…").font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if state == .installed { onSelect() } }
        .swipeActions {
            if state == .installed, let onDelete {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .notDownloaded, .failed:
            Button { app.store.download(model) } label: {
                Image(systemName: "arrow.down.circle").font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Download \(model.name)")
        case .downloading:
            Button { app.store.cancelDownload(model) } label: {
                Image(systemName: "xmark.circle").font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cancel download")
        case .verifying:
            EmptyView()
        case .installed:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .accessibilityLabel(isSelected ? "Selected" : "Select")
        }
    }
}

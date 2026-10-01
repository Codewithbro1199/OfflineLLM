import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    let onFinish: () -> Void

    private var anyInstalled: Bool { !app.store.installedModels.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text("AI that works offline")
                            .font(.largeTitle.bold())
                        Text("Offgrid runs a language model directly on your iPhone. After a one-time download, it answers without internet, and your chats never leave the device.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Point(icon: "lock.shield", title: "Private", text: "No account, no servers, no tracking.")
                        Point(icon: "airplane", title: "Offline", text: "Works in airplane mode, abroad, or off the grid.")
                        Point(icon: "exclamationmark.bubble", title: "Honest limits", text: "Small models can be wrong. Double-check anything important.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose a model to download").font(.headline)
                        VStack(spacing: 0) {
                            ForEach(ModelCatalog.all) { model in
                                ModelRow(model: model, isSelected: app.selectedModelID == model.id,
                                         onSelect: { app.select(model) })
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                if model.id != ModelCatalog.all.last?.id { Divider().padding(.leading, 14) }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        Text("Tip: keep Offgrid open on Wi-Fi for the fastest download. It continues in the background too.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button(action: onFinish) {
                    Text(anyInstalled ? "Start chatting" : "Download a model to continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!anyInstalled)
                .padding(20)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !anyInstalled {
                        Button("Later", action: onFinish)
                    }
                }
            }
        }
        .interactiveDismissDisabled(!anyInstalled)
        .onChange(of: anyInstalled) { _, installed in
            if installed { app.refreshSelection() }
        }
    }
}

private struct Point: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

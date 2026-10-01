import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(ChatController.self) private var chat
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle("Think before answering", isOn: $app.settings.thinking)
            } footer: {
                Text("The model reasons step by step first. Better for maths and tricky questions, but much slower.")
            }

            Section {
                VStack(alignment: .leading) {
                    LabeledContent("Creativity", value: String(format: "%.1f", app.settings.temperature))
                    Slider(value: $app.settings.temperature, in: 0...1.5, step: 0.1)
                }
                Picker("Memory (context)", selection: $app.settings.contextLength) {
                    ForEach(AppSettings.contextOptions, id: \.self) { value in
                        Text("\(value / 1024)K tokens").tag(value)
                    }
                }
                Picker("Longest reply", selection: $app.settings.maxNewTokens) {
                    Text("Short").tag(512)
                    Text("Medium").tag(1536)
                    Text("Long").tag(4096)
                }
            } header: {
                Text("Answers")
            } footer: {
                Text("More context lets the model remember longer chats but uses more memory. Older messages are dropped when a chat outgrows it.")
            }
            .disabled(chat.isGenerating)

            Section {
                TextEditor(text: $app.settings.systemPrompt)
                    .frame(minHeight: 120)
                    .font(.callout)
                Button("Reset to default") { app.settings.systemPrompt = AppSettings.defaultSystemPrompt }
                    .disabled(app.settings.systemPrompt == AppSettings.defaultSystemPrompt)
            } header: {
                Text("Instructions for the model")
            }

            Section {
                Button("Delete all chats", role: .destructive) { confirmDeleteAll = true }
            } footer: {
                Text("Chats are stored only on this iPhone.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.versionString)
                LabeledContent("Engine", value: "llama.cpp (Metal)")
                LabeledContent("Network", value: "Only for model downloads")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .confirmationDialog("Delete all chats?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive, action: deleteAll)
        } message: {
            Text("This can't be undone.")
        }
    }

    private func deleteAll() {
        chat.stop()
        let all = (try? context.fetch(FetchDescriptor<Conversation>())) ?? []
        all.forEach { context.delete($0) }
        try? context.save()
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

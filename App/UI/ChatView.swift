import SwiftData
import SwiftUI

struct ChatView: View {
    @Bindable var conversation: Conversation
    @Environment(AppModel.self) private var app
    @Environment(ChatController.self) private var chat
    @Environment(\.modelContext) private var context

    @State private var draft = ""
    @State private var showModels = false
    @FocusState private var composerFocused: Bool

    private var messages: [Message] { conversation.sortedMessages }
    private var isGeneratingHere: Bool { chat.activeConversationID == conversation.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty { emptyState }
                    ForEach(messages) { message in
                        MessageView(
                            message: message,
                            isStreaming: isGeneratingHere && message.id == messages.last?.id,
                            isThinkingNow: chat.isThinkingNow,
                            canRegenerate: !chat.isGenerating && message.id == messages.last?.id && message.role == .assistant,
                            onRegenerate: { chat.regenerate(in: conversation, context: context) }
                        )
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.text) { _, _ in
                if isGeneratingHere { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
        }
        .sheet(isPresented: $showModels) { NavigationStack { ModelsView() } }
    }

    private var header: some View {
        Button { showModels = true } label: {
            VStack(spacing: 1) {
                Text(conversation.title).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose a model")
    }

    private var statusText: String {
        switch app.engineState {
        case .noModel: return "No model — tap to download"
        case .idle: return app.selectedModel?.name ?? "No model"
        case .loading(let name): return "Loading \(name)…"
        case .ready(let name): return "\(name) · offline"
        case .failed: return "Model failed to load"
        }
    }

    private var statusColor: Color {
        switch app.engineState {
        case .ready: return .green
        case .loading: return .orange
        case .failed, .noModel: return .red
        case .idle: return .secondary
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask anything").font(.title2.bold())
            Text("Answers are generated on this iPhone. Nothing leaves the device, and it works in airplane mode.")
                .foregroundStyle(.secondary)
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button {
                    draft = suggestion
                    composerFocused = true
                } label: {
                    Text(suggestion)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 24)
    }

    private static let suggestions = [
        "Explain how a heat pump works, simply",
        "Write a polite message declining a meeting",
        "What should I pack for a 3-day hike?",
    ]

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.quaternary))

            if isGeneratingHere {
                Button { chat.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 32))
                }
                .accessibilityLabel("Stop")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .disabled(draft.trimmed.isEmpty || chat.isGenerating)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        guard app.hasUsableModel else {
            showModels = true
            return
        }
        let text = draft
        draft = ""
        chat.send(text, in: conversation, context: context)
    }
}

import SwiftData
import SwiftUI

struct ConversationListView: View {
    @Environment(AppModel.self) private var app
    @Environment(ChatController.self) private var chat
    @Environment(\.modelContext) private var context
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var path: [UUID] = []
    @State private var showModels = false
    @State private var showSettings = false
    @State private var search = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { conversation in
                    NavigationLink(value: conversation.id) {
                        ConversationRow(conversation: conversation,
                                        isActive: chat.activeConversationID == conversation.id)
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .overlay {
                if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("No chats yet", systemImage: "bubble.left.and.text.bubble.right")
                    } description: {
                        Text("Everything you ask stays on this iPhone and works without internet.")
                    } actions: {
                        Button("Start a chat", action: newChat).buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search chats")
            .navigationTitle("Offgrid")
            .navigationDestination(for: UUID.self) { id in
                if let conversation = conversations.first(where: { $0.id == id }) {
                    ChatView(conversation: conversation)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showModels = true } label: { Label("Models", systemImage: "cpu") }
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: newChat) { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New chat")
                }
            }
            .sheet(isPresented: $showModels) { NavigationStack { ModelsView() } }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        }
    }

    private var filtered: [Conversation] {
        let query = search.trimmed
        guard !query.isEmpty else { return conversations }
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    private func newChat() {
        // Reuse an untouched empty chat instead of piling them up.
        if let empty = conversations.first(where: { $0.messages.isEmpty }) {
            path = [empty.id]
            return
        }
        let conversation = Conversation()
        context.insert(conversation)
        try? context.save()
        path = [conversation.id]
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let conversation = filtered[index]
            if chat.activeConversationID == conversation.id { chat.stop() }
            context.delete(conversation)
        }
        try? context.save()
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title).font(.headline).lineLimit(1)
                Spacer()
                if isActive {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !conversation.preview.isEmpty {
                Text(conversation.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

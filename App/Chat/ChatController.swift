import Foundation
import Observation
import SwiftData

/// Runs one generation at a time and streams it into a SwiftData message.
@MainActor
@Observable
final class ChatController {
    private(set) var activeConversationID: UUID?
    private(set) var isThinkingNow = false
    var lastError: String?

    @ObservationIgnored private var generationTask: Task<Void, Never>?
    private let app: AppModel

    init(app: AppModel) { self.app = app }

    var isGenerating: Bool { activeConversationID != nil }

    func send(_ text: String, in conversation: Conversation, context: ModelContext) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, !isGenerating else { return }
        let userMessage = Message(role: .user, text: trimmed)
        conversation.messages.append(userMessage)
        if conversation.messages.count == 1 { conversation.title = ConversationTitle.from(trimmed) }
        conversation.updatedAt = .now
        try? context.save()
        respond(in: conversation, context: context)
    }

    /// Replaces the last assistant reply with a fresh one.
    func regenerate(in conversation: Conversation, context: ModelContext) {
        guard !isGenerating, let last = conversation.sortedMessages.last, last.role == .assistant else { return }
        conversation.messages.removeAll { $0.id == last.id }
        context.delete(last)
        try? context.save()
        respond(in: conversation, context: context)
    }

    func stop() {
        generationTask?.cancel()
    }

    private func respond(in conversation: Conversation, context: ModelContext) {
        let history = conversation.sortedMessages
        var turns: [ChatTurn] = []
        let system = app.settings.systemPrompt.trimmed
        if !system.isEmpty { turns.append(ChatTurn(role: .system, content: system)) }
        for message in history where message.errorText == nil && !message.text.isEmpty {
            turns.append(ChatTurn(role: message.role, content: message.modelFacingText))
        }

        let reply = Message(role: .assistant, text: "", modelName: app.selectedModel?.name)
        conversation.messages.append(reply)
        activeConversationID = conversation.id
        lastError = nil
        let options = app.generationOptions

        generationTask = Task { [weak self] in
            guard let self else { return }
            var raw = ""
            var lastFlush = Date.distantPast
            do {
                try await self.app.prepareEngine()
                for try await event in self.app.engine.generate(turns: turns, options: options) {
                    guard Self.isAlive(conversation, reply) else { break }
                    switch event {
                    case .text(let piece):
                        raw += piece
                        if Date().timeIntervalSince(lastFlush) > 0.05 {
                            self.apply(raw, to: reply)
                            lastFlush = Date()
                        }
                    case .finished(let stats):
                        reply.tokensPerSecond = stats.tokensPerSecond
                        // Reasoning isn't fed back to the model, so only direct answers keep a transcript.
                        if !options.thinking { reply.transcript = stats.transcript }
                    }
                }
                guard Self.isAlive(conversation, reply) else { return self.reset() }
                self.apply(raw, to: reply)
                if reply.text.isEmpty && reply.thinking.isEmpty && !Task.isCancelled {
                    reply.errorText = "The model returned an empty reply. Try again or rephrase."
                }
            } catch is CancellationError {
                guard Self.isAlive(conversation, reply) else { return self.reset() }
                self.apply(raw, to: reply)
            } catch {
                guard Self.isAlive(conversation, reply) else { return self.reset() }
                self.apply(raw, to: reply)
                reply.errorText = error.localizedDescription
                self.lastError = error.localizedDescription
            }
            if reply.text.isEmpty && reply.thinking.isEmpty && reply.errorText == nil {
                conversation.messages.removeAll { $0.id == reply.id }
                context.delete(reply)
            }
            conversation.updatedAt = .now
            try? context.save()
            self.reset()
        }
    }

    private func reset() {
        isThinkingNow = false
        activeConversationID = nil
        generationTask = nil
    }

    /// False once the chat (or the reply) was deleted while the answer was still streaming.
    private static func isAlive(_ conversation: Conversation, _ reply: Message) -> Bool {
        !conversation.isDeleted && !reply.isDeleted && conversation.modelContext != nil
    }

    private func apply(_ raw: String, to message: Message) {
        let split = ThinkSplit(raw: raw)
        if message.text != split.answer { message.text = split.answer }
        if message.thinking != split.thinking { message.thinking = split.thinking }
        if isThinkingNow != split.isThinking { isThinkingNow = split.isThinking }
    }
}

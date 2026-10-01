import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(title: String = "New chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var preview: String {
        sortedMessages.last?.text.trimmed.prefix(80).description ?? ""
    }
}

@Model
final class Message {
    var id: UUID
    var roleRaw: String
    var text: String
    var thinking: String
    var createdAt: Date
    var modelName: String?
    var tokensPerSecond: Double?
    var errorText: String?
    /// What the model actually produced, including hidden pre-filled tokens. Used as the
    /// model-facing history so the engine can reuse its memory on the next turn.
    var transcript: String?
    var conversation: Conversation?

    init(role: ChatTurn.Role, text: String, thinking: String = "", modelName: String? = nil) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.thinking = thinking
        self.createdAt = .now
        self.modelName = modelName
    }

    var role: ChatTurn.Role { ChatTurn.Role(rawValue: roleRaw) ?? .user }

    /// The text the model should see for this message in later turns.
    var modelFacingText: String {
        if role == .assistant, let transcript, !transcript.isEmpty { return transcript }
        return text
    }
}

enum ConversationTitle {
    /// A short title from the first user message.
    static func from(_ text: String, limit: Int = 40) -> String {
        let singleLine = text.trimmed.replacingOccurrences(of: "\n", with: " ")
        guard !singleLine.isEmpty else { return "New chat" }
        if singleLine.count <= limit { return singleLine }
        let cut = singleLine.prefix(limit)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }
}

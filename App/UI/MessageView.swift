import SwiftUI
import UIKit

struct MessageView: View {
    let message: Message
    let isStreaming: Bool
    let isThinkingNow: Bool
    let canRegenerate: Bool
    let onRegenerate: () -> Void

    @State private var showThinking = false

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                    .contextMenu { copyButton }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !message.thinking.isEmpty || (isStreaming && isThinkingNow) {
                    thinkingSection
                }
                if !message.text.isEmpty {
                    MarkdownText(message.text)
                        .contextMenu {
                            copyButton
                            if canRegenerate {
                                Button(action: onRegenerate) { Label("Regenerate", systemImage: "arrow.clockwise") }
                            }
                        }
                } else if isStreaming && !isThinkingNow {
                    TypingIndicator()
                }
                if let error = message.errorText {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if !isStreaming { footer }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var thinkingSection: some View {
        DisclosureGroup(isExpanded: $showThinking) {
            Text(message.thinking)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 6) {
                if isStreaming && isThinkingNow { ProgressView().controlSize(.mini) }
                Text(isStreaming && isThinkingNow ? "Thinking…" : "Reasoning")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var footer: some View {
        let parts = [message.modelName, message.tokensPerSecond.map { String(format: "%.1f tok/s", $0) }].compactMap { $0 }
        if !parts.isEmpty || canRegenerate {
            HStack(spacing: 12) {
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy")
                }
                if canRegenerate {
                    Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Regenerate")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.text
        } label: { Label("Copy", systemImage: "doc.on.doc") }
    }
}

private struct TypingIndicator: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title2)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .accessibilityLabel("Preparing answer")
    }
}

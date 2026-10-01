import Foundation

/// Minimal ChatML renderer, used when a model ships no usable chat template.
enum ChatML {
    static let noThinkPrefill = "<think>\n\n</think>\n\n"

    static func render(_ turns: [ChatTurn]) -> String {
        var text = ""
        for turn in turns {
            text += "<|im_start|>\(turn.role.rawValue)\n\(turn.content)<|im_end|>\n"
        }
        text += "<|im_start|>assistant\n"
        return text
    }

    /// Qwen3-family templates understand an empty `<think></think>` block as "answer directly".
    static func supportsThinkPrefill(template: String?) -> Bool {
        guard let template else { return false }
        return template.contains("<think>") && template.contains("<|im_start|>")
    }
}

enum PromptTrimmer {
    /// The oldest turn that can be dropped to save context: never the system prompt, never the latest message.
    static func indexToDrop(in turns: [ChatTurn]) -> Int? {
        guard turns.count > 1 else { return nil }
        for index in 0..<(turns.count - 1) where turns[index].role != .system {
            return index
        }
        return nil
    }

    static func commonPrefixLength<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        var index = 0
        let limit = min(a.count, b.count)
        while index < limit, a[index] == b[index] { index += 1 }
        return index
    }
}

/// Collects token bytes and only releases complete UTF-8 characters, so emoji and
/// non-Latin scripts split across tokens never render as garbage.
struct UTF8Accumulator {
    private var pending: [UInt8] = []

    mutating func append(_ bytes: [UInt8]) -> String {
        pending.append(contentsOf: bytes)
        let cut = UTF8Accumulator.completePrefixLength(pending)
        guard cut > 0 else { return "" }
        let text = String(decoding: pending[..<cut], as: UTF8.self)
        pending.removeFirst(cut)
        return text
    }

    mutating func flush() -> String {
        defer { pending.removeAll() }
        return pending.isEmpty ? "" : String(decoding: pending, as: UTF8.self)
    }

    /// Length of the prefix that doesn't end in the middle of a multi-byte character.
    static func completePrefixLength(_ bytes: [UInt8]) -> Int {
        let count = bytes.count
        var index = count - 1
        var continuation = 0
        while index >= 0, continuation < 3, bytes[index] & 0xC0 == 0x80 {
            continuation += 1
            index -= 1
        }
        guard index >= 0 else { return count }
        let lead = bytes[index]
        let needed: Int
        switch lead {
        case 0xF0...0xF7: needed = 4
        case 0xE0...0xEF: needed = 3
        case 0xC0...0xDF: needed = 2
        default: needed = 1
        }
        let available = count - index
        return available < needed ? index : count
    }
}

/// Splits raw model output into its reasoning part and its visible answer.
struct ThinkSplit: Equatable {
    var thinking: String
    var answer: String
    /// True while the model is still inside an unclosed reasoning block.
    var isThinking: Bool

    init(thinking: String, answer: String, isThinking: Bool) {
        self.thinking = thinking
        self.answer = answer
        self.isThinking = isThinking
    }

    init(raw: String) {
        let open = "<think>", close = "</think>"
        if let openRange = raw.range(of: open) {
            let before = String(raw[..<openRange.lowerBound])
            let rest = raw[openRange.upperBound...]
            if let closeRange = rest.range(of: close) {
                self.init(thinking: String(rest[..<closeRange.lowerBound]).trimmed,
                          answer: (before + rest[closeRange.upperBound...]).trimmed,
                          isThinking: false)
            } else {
                self.init(thinking: String(rest).trimmed, answer: before.trimmed, isThinking: true)
            }
        } else if let closeRange = raw.range(of: close) {
            self.init(thinking: String(raw[..<closeRange.lowerBound]).trimmed,
                      answer: String(raw[closeRange.upperBound...]).trimmed,
                      isThinking: false)
        } else {
            self.init(thinking: "", answer: raw.trimmed, isThinking: false)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

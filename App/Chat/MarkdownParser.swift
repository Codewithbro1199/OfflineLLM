import Foundation

/// A tiny block-level Markdown parser: enough for chat answers (headings, lists, code, quotes).
/// Inline styling (bold, italics, code, links) is left to `AttributedString`.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String, indent: Int)
    case numbered(number: String, text: String, indent: Int)
    case code(language: String, code: String)
    case quote(String)
    case rule
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String]? = nil
        var codeLanguage = ""

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if codeLines != nil {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, code: codeLines!.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines!.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flushParagraph()
                codeLanguage = String(trimmed.dropFirst(3)).trimmed
                codeLines = []
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if let heading = headingLevel(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading, text: String(trimmed.dropFirst(heading)).trimmed))
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmed))
                continue
            }
            let indent = (line.count - line.drop(while: { $0 == " " }).count) / 2
            if let bullet = bulletText(trimmed) {
                flushParagraph()
                blocks.append(.bullet(text: bullet, indent: indent))
                continue
            }
            if let item = numberedItem(trimmed) {
                flushParagraph()
                blocks.append(.numbered(number: item.number, text: item.text, indent: indent))
                continue
            }
            paragraph.append(trimmed)
        }
        if let codeLines {
            // Unclosed fence while streaming: still show it as code.
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> (number: String, text: String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (String(digits), String(rest.dropFirst(2)))
    }
}

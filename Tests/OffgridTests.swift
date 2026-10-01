import XCTest
@testable import Offgrid

final class PromptSupportTests: XCTestCase {
    func testUTF8AccumulatorHoldsSplitEmoji() {
        var acc = UTF8Accumulator()
        let bytes = Array("a😀b".utf8) // 😀 is 4 bytes
        XCTAssertEqual(acc.append(Array(bytes[0..<2])), "a")
        XCTAssertEqual(acc.append(Array(bytes[2..<4])), "")
        XCTAssertEqual(acc.append(Array(bytes[4..<6])), "😀b")
        XCTAssertEqual(acc.flush(), "")
    }

    func testUTF8AccumulatorFlushesLeftovers() {
        var acc = UTF8Accumulator()
        XCTAssertEqual(acc.append([0xE2, 0x82]), "")
        XCTAssertFalse(acc.flush().isEmpty) // invalid tail becomes a replacement char, not lost silently
    }

    func testThinkSplitClosedBlock() {
        let split = ThinkSplit(raw: "<think>\nplan it\n</think>\n\nThe answer.")
        XCTAssertEqual(split, ThinkSplit(thinking: "plan it", answer: "The answer.", isThinking: false))
    }

    func testThinkSplitStreamingBlock() {
        let split = ThinkSplit(raw: "<think>still going")
        XCTAssertTrue(split.isThinking)
        XCTAssertEqual(split.answer, "")
        XCTAssertEqual(split.thinking, "still going")
    }

    func testThinkSplitCloseOnly() {
        let split = ThinkSplit(raw: "reasoning</think>Answer")
        XCTAssertEqual(split.thinking, "reasoning")
        XCTAssertEqual(split.answer, "Answer")
    }

    func testThinkSplitPlain() {
        XCTAssertEqual(ThinkSplit(raw: " Hello ").answer, "Hello")
    }

    func testTrimmerKeepsSystemAndLatest() {
        let turns = [
            ChatTurn(role: .system, content: "s"),
            ChatTurn(role: .user, content: "u1"),
            ChatTurn(role: .assistant, content: "a1"),
            ChatTurn(role: .user, content: "u2"),
        ]
        XCTAssertEqual(PromptTrimmer.indexToDrop(in: turns), 1)
        XCTAssertNil(PromptTrimmer.indexToDrop(in: [turns[0], turns[3]]))
        XCTAssertNil(PromptTrimmer.indexToDrop(in: [turns[3]]))
    }

    func testCommonPrefix() {
        XCTAssertEqual(PromptTrimmer.commonPrefixLength([1, 2, 3], [1, 2, 4, 5]), 2)
        XCTAssertEqual(PromptTrimmer.commonPrefixLength([Int](), [1]), 0)
    }

    func testChatMLRender() {
        let text = ChatML.render([ChatTurn(role: .user, content: "hi")])
        XCTAssertEqual(text, "<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n")
        XCTAssertTrue(ChatML.supportsThinkPrefill(template: "<|im_start|>{% if <think> %}"))
        XCTAssertFalse(ChatML.supportsThinkPrefill(template: nil))
    }
}

final class MarkdownParserTests: XCTestCase {
    func testBlocks() {
        let source = """
        # Title
        Some *text*
        continues here.

        - one
          - nested
        2. two
        > quote
        ```swift
        let x = 1
        ```
        ---
        """
        XCTAssertEqual(MarkdownParser.parse(source), [
            .heading(level: 1, text: "Title"),
            .paragraph("Some *text*\ncontinues here."),
            .bullet(text: "one", indent: 0),
            .bullet(text: "nested", indent: 1),
            .numbered(number: "2", text: "two", indent: 0),
            .quote("quote"),
            .code(language: "swift", code: "let x = 1"),
            .rule,
        ])
    }

    func testUnclosedFenceStillCode() {
        XCTAssertEqual(MarkdownParser.parse("```\nabc"), [.code(language: "", code: "abc")])
    }

    func testHashtagIsNotHeading() {
        XCTAssertEqual(MarkdownParser.parse("#hashtag"), [.paragraph("#hashtag")])
    }
}

final class CatalogTests: XCTestCase {
    func testCatalogEntriesArePinnedAndHashed() {
        XCTAssertNotNil(ModelCatalog.model(id: ModelCatalog.defaultModelID))
        XCTAssertEqual(Set(ModelCatalog.all.map(\.id)).count, ModelCatalog.all.count)
        for model in ModelCatalog.all {
            XCTAssertEqual(model.url.scheme, "https")
            XCTAssertTrue(model.url.path.contains("/resolve/"), model.id)
            XCTAssertTrue(model.url.path.hasSuffix(model.fileName), model.id)
            XCTAssertEqual(model.sha256.count, 64, model.id)
            XCTAssertTrue(model.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase }, model.id)
            XCTAssertGreaterThan(model.bytes, 100_000_000)
        }
    }

    func testSHA256OfFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hash-test.txt")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ModelStore.sha256(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testConversationTitle() {
        XCTAssertEqual(ConversationTitle.from("  Hello\nthere "), "Hello there")
        XCTAssertEqual(ConversationTitle.from(""), "New chat")
        let long = ConversationTitle.from("How do I make a sourdough starter from scratch at home?")
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertLessThanOrEqual(long.count, 41)
    }
}

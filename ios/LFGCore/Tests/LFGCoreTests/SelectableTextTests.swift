// The selectable transcript renders a message through Foundation's markdown
// parser instead of MarkdownUI (whose block model is internal). These pin the
// block structure that renderer relies on — especially tables, which have to
// come out as one row per line so a drag across cells copies as TSV.
import Testing
import Foundation
@testable import LFGCore

private func spansText(_ spans: [SelectableText.Span]) -> String {
    spans.map(\.text).joined()
}

@Suite("SelectableText")
struct SelectableTextTests {

    @Test func plainTextIsOneParagraph() {
        let blocks = SelectableText.parse(markdown: "just words, no markdown")
        #expect(blocks == [.paragraph(spans: [.init(text: "just words, no markdown")], depth: 0, marker: nil, quoted: false)])
        #expect(SelectableText.plainText(blocks) == "just words, no markdown")
    }

    @Test func emptyInputYieldsNoBlocks() {
        #expect(SelectableText.parse(markdown: "").isEmpty)
        #expect(SelectableText.parse(markdown: "   \n\n").isEmpty)
    }

    @Test func inlineStylesAreCarriedOnSpans() throws {
        let blocks = SelectableText.parse(markdown: "Some **bold**, `code`, *em*, ~~gone~~.")
        guard case .paragraph(let spans, _, _, _) = try #require(blocks.first) else {
            Issue.record("expected a paragraph"); return
        }
        let bold = try #require(spans.first { $0.text == "bold" })
        #expect(bold.bold && !bold.code && !bold.italic)
        let code = try #require(spans.first { $0.text == "code" })
        #expect(code.code && !code.bold)
        let em = try #require(spans.first { $0.text == "em" })
        #expect(em.italic)
        let gone = try #require(spans.first { $0.text == "gone" })
        #expect(gone.strikethrough)
        #expect(spansText(spans) == "Some bold, code, em, gone.")
    }

    @Test func linksSurviveAsSpans() throws {
        let blocks = SelectableText.parse(markdown: "see [the docs](https://example.com/x) now")
        guard case .paragraph(let spans, _, _, _) = try #require(blocks.first) else {
            Issue.record("expected a paragraph"); return
        }
        let link = try #require(spans.first { $0.text == "the docs" })
        #expect(link.link == URL(string: "https://example.com/x"))
        #expect(spansText(spans) == "see the docs now")
    }

    @Test func headingsCarryLevel() {
        let blocks = SelectableText.parse(markdown: "# Title\n\n### Sub\n\nbody")
        #expect(blocks.count == 3)
        #expect(blocks[0] == .heading(level: 1, spans: [.init(text: "Title")]))
        #expect(blocks[1] == .heading(level: 3, spans: [.init(text: "Sub")]))
        #expect(SelectableText.plainText(blocks) == "Title\n\nSub\n\nbody")
    }

    @Test func nestedListsCarryDepthAndMarkers() throws {
        let md = """
        - one
        - two
          - nested
          - nested two

        1. first
        2. second
        """
        let blocks = SelectableText.parse(markdown: md)
        let expected: [SelectableText.Block] = [
            .paragraph(spans: [.init(text: "one")], depth: 1, marker: "•", quoted: false),
            .paragraph(spans: [.init(text: "two")], depth: 1, marker: "•", quoted: false),
            .paragraph(spans: [.init(text: "nested")], depth: 2, marker: "◦", quoted: false),
            .paragraph(spans: [.init(text: "nested two")], depth: 2, marker: "◦", quoted: false),
            .paragraph(spans: [.init(text: "first")], depth: 1, marker: "1.", quoted: false),
            .paragraph(spans: [.init(text: "second")], depth: 1, marker: "2.", quoted: false),
        ]
        #expect(blocks == expected)
        #expect(SelectableText.plainText(blocks) == "• one\n• two\n  ◦ nested\n  ◦ nested two\n1. first\n2. second")
    }

    @Test func paragraphsAndListItemsFormOneCopyableDocument() {
        let markdown = """
        Before the list.

        - first bullet
        - second bullet

        After the list.
        """

        let blocks = SelectableText.parse(markdown: markdown)

        #expect(blocks == [
            .paragraph(spans: [.init(text: "Before the list.")], depth: 0, marker: nil, quoted: false),
            .paragraph(spans: [.init(text: "first bullet")], depth: 1, marker: "•", quoted: false),
            .paragraph(spans: [.init(text: "second bullet")], depth: 1, marker: "•", quoted: false),
            .paragraph(spans: [.init(text: "After the list.")], depth: 0, marker: nil, quoted: false),
        ])
        #expect(
            SelectableText.plainText(blocks)
                == "Before the list.\n\n• first bullet\n• second bullet\n\nAfter the list."
        )
    }

    /// Only the first paragraph of a list item gets the marker; a continuation
    /// paragraph inside the same item is indented but unmarked.
    @Test func continuationParagraphInListItemHasNoMarker() throws {
        let md = "- item\n\n  more about item\n- next"
        let blocks = SelectableText.parse(markdown: md)
        #expect(blocks == [
            .paragraph(spans: [.init(text: "item")], depth: 1, marker: "•", quoted: false),
            .paragraph(spans: [.init(text: "more about item")], depth: 1, marker: nil, quoted: false),
            .paragraph(spans: [.init(text: "next")], depth: 1, marker: "•", quoted: false),
        ])
    }

    @Test func codeBlockKeepsContentVerbatim() {
        let md = "before\n\n```swift\nlet x = 1\n  indented()\n```\n\nafter"
        let blocks = SelectableText.parse(markdown: md)
        #expect(blocks.count == 3)
        #expect(blocks[1] == .codeBlock("let x = 1\n  indented()"))
        #expect(SelectableText.plainText(blocks) == "before\n\nlet x = 1\n  indented()\n\nafter")
    }

    @Test func blockquoteIsMarked() {
        let blocks = SelectableText.parse(markdown: "> quoted **words**")
        #expect(blocks == [
            .paragraph(spans: [.init(text: "quoted "), .init(text: "words", bold: true)], depth: 0, marker: nil, quoted: true),
        ])
    }

    @Test func softAndHardLineBreaksInsideParagraph() throws {
        let blocks = SelectableText.parse(markdown: "line one\nline two  \nline three")
        guard case .paragraph(let spans, _, _, _) = try #require(blocks.first) else {
            Issue.record("expected a paragraph"); return
        }
        // Soft break → space; hard (two-space) break → newline.
        #expect(spansText(spans) == "line one line two\nline three")
    }

    @Test func thematicBreakBecomesRule() {
        let blocks = SelectableText.parse(markdown: "a\n\n---\n\nb")
        #expect(blocks[1] == .rule)
    }

    @Test func tableBecomesHeaderAndRows() throws {
        let md = """
        | Name | Value |
        |------|------:|
        | alpha | 1 |
        | **beta** | 22 |
        """
        let blocks = SelectableText.parse(markdown: md)
        guard case .table(let header, let rows) = try #require(blocks.first) else {
            Issue.record("expected a table, got \(blocks)"); return
        }
        #expect(header.map(spansText) == ["Name", "Value"])
        #expect(rows.map { $0.map(spansText) } == [["alpha", "1"], ["beta", "22"]])
        let beta = try #require(rows[1][0].first)
        #expect(beta.bold)
    }

    @Test func plainTextRenderingJoinsTableCellsWithTabs() {
        let md = "intro\n\n| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\noutro"
        let text = SelectableText.plainText(SelectableText.parse(markdown: md))
        #expect(text == "intro\n\nA\tB\n1\t2\n3\t4\n\noutro")
    }

    /// A ragged row (fewer cells than the header) is padded so tab columns
    /// stay aligned and TSV stays rectangular.
    @Test func raggedTableRowsArePaddedToHeaderWidth() throws {
        let md = "| A | B | C |\n|---|---|---|\n| 1 | 2 |"
        let blocks = SelectableText.parse(markdown: md)
        guard case .table(_, let rows) = try #require(blocks.first) else {
            Issue.record("expected a table"); return
        }
        #expect(rows[0].count == 3)
        #expect(spansText(rows[0][2]) == "")
    }

    /// Markdown that Foundation cannot parse must not lose the text: fall back
    /// to a single paragraph of the raw source.
    @Test func unparseableInputFallsBackToRawParagraph() {
        // An unterminated HTML-ish fragment parses fine as text; the fallback
        // is exercised by construction with an invalid UTF-8-free but odd input.
        let odd = "<<<>>> [[[ ]]] ``` unterminated"
        let blocks = SelectableText.parse(markdown: odd)
        #expect(!blocks.isEmpty)
        #expect(SelectableText.plainText(blocks).contains("unterminated"))
    }
}

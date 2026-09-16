import Foundation

/// Block model behind the "Select Text" sheet.
///
/// The transcript renders markdown through MarkdownUI, whose parsed block tree
/// is internal and whose blocks are separate SwiftUI `Text`s — on iOS that
/// gives "long-press → Copy the whole block" and nothing finer. The sheet
/// instead needs ONE native text view holding the whole message, so it needs
/// its own structure. Foundation's markdown parser (`.full` interpreted
/// syntax) emits presentation intents for everything the transcript uses —
/// headings, inline styles, links, nested lists, code blocks, quotes and GFM
/// tables (down to the cell) — and this walks those intents into a flat list
/// of blocks the UIKit renderer can lay out.
///
/// Pure Foundation so it runs under `swift test` on macOS; fonts and colours
/// are the app target's business.
public enum SelectableText {

    /// A run of inline text with its styling. Adjacent runs with identical
    /// styling are merged.
    public struct Span: Equatable, Sendable {
        public var text: String
        public var bold: Bool
        public var italic: Bool
        public var code: Bool
        public var strikethrough: Bool
        public var link: URL?

        public init(
            text: String,
            bold: Bool = false,
            italic: Bool = false,
            code: Bool = false,
            strikethrough: Bool = false,
            link: URL? = nil
        ) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.code = code
            self.strikethrough = strikethrough
            self.link = link
        }

        /// True when two spans differ only in text and can be joined.
        func sameStyle(as other: Span) -> Bool {
            bold == other.bold && italic == other.italic && code == other.code
                && strikethrough == other.strikethrough && link == other.link
        }
    }

    public enum Block: Equatable, Sendable {
        /// `depth` is the list nesting level (0 outside any list). `marker` is
        /// the bullet / ordinal rendered before the first paragraph of a list
        /// item and nil for continuation paragraphs. `quoted` marks a
        /// blockquote paragraph.
        case paragraph(spans: [Span], depth: Int, marker: String?, quoted: Bool)
        case heading(level: Int, spans: [Span])
        case codeBlock(String)
        /// `rows` are padded to the header's column count so tab columns stay
        /// aligned and copied text is rectangular TSV.
        case table(header: [[Span]], rows: [[[Span]]])
        case rule
    }

    // MARK: - Parse

    public static func parse(markdown: String) -> [Block] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard let attributed = try? AttributedString(markdown: markdown, options: options) else {
            return [.paragraph(spans: [Span(text: trimmed)], depth: 0, marker: nil, quoted: false)]
        }

        var builder = Builder()
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            let components = run.presentationIntent?.components ?? []
            let span = makeSpan(text: text, run: run)
            builder.consume(span: span, components: components)
        }
        let blocks = builder.finish()

        // Never lose the text: if the walk produced nothing for a non-empty
        // source, show the source as-is.
        if blocks.isEmpty {
            return [.paragraph(spans: [Span(text: trimmed)], depth: 0, marker: nil, quoted: false)]
        }
        return blocks
    }

    private static func makeSpan(text: String, run: AttributedString.Runs.Run) -> Span {
        let inline = run.inlinePresentationIntent ?? []
        return Span(
            text: text,
            bold: inline.contains(.stronglyEmphasized),
            italic: inline.contains(.emphasized),
            code: inline.contains(.code),
            strikethrough: inline.contains(.strikethrough),
            link: run.link
        )
    }

    // MARK: - Plain text

    /// The blocks as plain text: list markers inline, table cells joined by
    /// tabs, blocks separated by a blank line (list items and table rows by a
    /// single newline). This is what "Copy All" produces when no rendered
    /// text view is at hand, and what the tests pin.
    public static func plainText(_ blocks: [Block]) -> String {
        var out: [String] = []
        var previousWasListItem = false
        for block in blocks {
            let isListItem: Bool
            if case .paragraph(_, let depth, _, _) = block, depth > 0 { isListItem = true } else { isListItem = false }
            let separator = (isListItem && previousWasListItem) ? "\n" : "\n\n"
            if !out.isEmpty { out.append(separator) }
            out.append(plainText(block))
            previousWasListItem = isListItem
        }
        return out.joined()
    }

    private static func plainText(_ block: Block) -> String {
        switch block {
        case .paragraph(let spans, let depth, let marker, _):
            let indent = String(repeating: "  ", count: max(0, depth - 1))
            let prefix = marker.map { "\($0) " } ?? (depth > 0 ? "" : "")
            return indent + prefix + join(spans)
        case .heading(_, let spans):
            return join(spans)
        case .codeBlock(let code):
            return code
        case .table(let header, let rows):
            let lines = [header] + rows
            return lines.map { $0.map(join).joined(separator: "\t") }.joined(separator: "\n")
        case .rule:
            return "———"
        }
    }

    private static func join(_ spans: [Span]) -> String {
        spans.map(\.text).joined()
    }

    // MARK: - Builder

    /// Walks runs in document order, opening a block when the run's block
    /// identity changes and closing the previous one.
    private struct Builder {
        private var blocks: [Block] = []
        private var open: Open?
        /// List items that already received their marker.
        private var markedItems: Set<Int> = []

        private enum Open {
            case paragraph(id: Int, spans: [Span], depth: Int, marker: String?, quoted: Bool)
            case heading(id: Int, level: Int, spans: [Span])
            case code(id: Int, text: String)
            case table(id: Int, table: TableBuilder)
            case rule(id: Int)

            var id: Int {
                switch self {
                case .paragraph(let id, _, _, _, _), .heading(let id, _, _), .code(let id, _),
                     .table(let id, _), .rule(let id):
                    return id
                }
            }
        }

        mutating func consume(span: Span, components: [PresentationIntent.IntentType]) {
            // Classify the run by its innermost block-level intent.
            var tableCell: (cellID: Int, column: Int)?
            var tableRow: (rowID: Int, isHeader: Bool)?
            var tableID: Int?
            var tableColumns: Int?
            var codeID: Int?
            var heading: (id: Int, level: Int)?
            var paragraphID: Int?
            var ruleID: Int?
            var quoted = false
            var listDepth = 0
            var innermostItem: (id: Int, ordinal: Int)?
            var innermostListOrdered: Bool?

            for component in components {
                switch component.kind {
                case .tableCell(let column):
                    tableCell = (component.identity, column)
                case .tableHeaderRow:
                    tableRow = (component.identity, true)
                case .tableRow:
                    tableRow = (component.identity, false)
                case .table(let columns):
                    tableID = component.identity
                    tableColumns = columns.count
                case .codeBlock:
                    codeID = component.identity
                case .header(let level):
                    heading = (component.identity, level)
                case .paragraph:
                    paragraphID = component.identity
                case .thematicBreak:
                    ruleID = component.identity
                case .blockQuote:
                    quoted = true
                case .listItem(let ordinal):
                    if innermostItem == nil { innermostItem = (component.identity, ordinal) }
                case .orderedList:
                    listDepth += 1
                    if innermostListOrdered == nil { innermostListOrdered = true }
                case .unorderedList:
                    listDepth += 1
                    if innermostListOrdered == nil { innermostListOrdered = false }
                @unknown default:
                    break
                }
            }

            if let tableID, let tableRow, let tableCell {
                if case .table(let id, var table) = open, id == tableID {
                    table.add(span: span, rowID: tableRow.rowID, isHeader: tableRow.isHeader,
                              cellID: tableCell.cellID, column: tableCell.column)
                    open = .table(id: id, table: table)
                } else {
                    close()
                    var table = TableBuilder(columnCount: tableColumns ?? 0)
                    table.add(span: span, rowID: tableRow.rowID, isHeader: tableRow.isHeader,
                              cellID: tableCell.cellID, column: tableCell.column)
                    open = .table(id: tableID, table: table)
                }
                return
            }

            if let codeID {
                if case .code(let id, let text) = open, id == codeID {
                    open = .code(id: id, text: text + span.text)
                } else {
                    close()
                    open = .code(id: codeID, text: span.text)
                }
                return
            }

            if let ruleID {
                if case .rule(let id) = open, id == ruleID { return }
                close()
                open = .rule(id: ruleID)
                return
            }

            if let heading {
                if case .heading(let id, let level, var spans) = open, id == heading.id {
                    append(span, to: &spans)
                    open = .heading(id: id, level: level, spans: spans)
                } else {
                    close()
                    open = .heading(id: heading.id, level: heading.level, spans: [span])
                }
                return
            }

            // Everything else is a paragraph; a run with no intent at all is a
            // paragraph of its own (identity -1 groups such runs together).
            let id = paragraphID ?? -1
            if case .paragraph(let openID, var spans, let depth, let marker, let q) = open, openID == id {
                append(span, to: &spans)
                open = .paragraph(id: openID, spans: spans, depth: depth, marker: marker, quoted: q)
                return
            }
            close()
            var marker: String?
            if let item = innermostItem, !markedItems.contains(item.id) {
                markedItems.insert(item.id)
                if innermostListOrdered == true {
                    marker = "\(item.ordinal)."
                } else {
                    marker = listDepth % 2 == 1 ? "•" : "◦"
                }
            }
            open = .paragraph(id: id, spans: [span], depth: listDepth, marker: marker, quoted: quoted)
        }

        private func append(_ span: Span, to spans: inout [Span]) {
            if let last = spans.last, last.sameStyle(as: span) {
                spans[spans.count - 1].text += span.text
            } else {
                spans.append(span)
            }
        }

        private mutating func close() {
            guard let open else { return }
            switch open {
            case .paragraph(_, let spans, let depth, let marker, let quoted):
                let trimmed = trimmingEdges(spans)
                if !trimmed.isEmpty {
                    blocks.append(.paragraph(spans: trimmed, depth: depth, marker: marker, quoted: quoted))
                }
            case .heading(_, let level, let spans):
                blocks.append(.heading(level: level, spans: trimmingEdges(spans)))
            case .code(_, let text):
                var code = text
                if code.hasSuffix("\n") { code.removeLast() }
                blocks.append(.codeBlock(code))
            case .table(_, let table):
                blocks.append(table.build())
            case .rule:
                blocks.append(.rule)
            }
            self.open = nil
        }

        /// Drops leading/trailing whitespace-only spans and trims the edges of
        /// the outer spans, so a paragraph never starts or ends on a stray
        /// soft break.
        private func trimmingEdges(_ spans: [Span]) -> [Span] {
            var result = spans
            while let first = result.first, first.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.removeFirst()
            }
            while let last = result.last, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.removeLast()
            }
            if !result.isEmpty {
                result[0].text = String(result[0].text.drop(while: { $0.isWhitespace }))
                let lastIndex = result.count - 1
                while let c = result[lastIndex].text.last, c.isWhitespace { result[lastIndex].text.removeLast() }
            }
            return result
        }

        mutating func finish() -> [Block] {
            close()
            return blocks
        }
    }

    /// Accumulates table cells in document order. Cells arrive as runs keyed
    /// by cell identity; a cell with several inline runs (bold + plain) arrives
    /// as several calls with the same `cellID`.
    private struct TableBuilder {
        private var columnCount: Int
        private var headerRowID: Int?
        private var rowOrder: [Int] = []
        private var cells: [Int: [Int: [Span]]] = [:]   // rowID → column → spans
        private var lastCellID: Int?

        init(columnCount: Int) {
            self.columnCount = columnCount
        }

        mutating func add(span: Span, rowID: Int, isHeader: Bool, cellID: Int, column: Int) {
            if isHeader { headerRowID = rowID }
            if cells[rowID] == nil {
                cells[rowID] = [:]
                rowOrder.append(rowID)
            }
            var spans = cells[rowID]?[column] ?? []
            if lastCellID == cellID, let last = spans.last, last.sameStyle(as: span) {
                spans[spans.count - 1].text += span.text
            } else {
                spans.append(span)
            }
            cells[rowID]?[column] = spans
            lastCellID = cellID
            columnCount = max(columnCount, column + 1)
        }

        func build() -> Block {
            func row(_ id: Int) -> [[Span]] {
                let columns = cells[id] ?? [:]
                return (0..<max(columnCount, 1)).map { columns[$0] ?? [] }
            }
            let header = headerRowID.map(row) ?? Array(repeating: [], count: max(columnCount, 1))
            let body = rowOrder.filter { $0 != headerRowID }.map(row)
            return .table(header: header, rows: body)
        }
    }
}

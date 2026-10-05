import Foundation

/// Rendering boundary for assistant Markdown.
///
/// Contiguous prose stays in one native text view so selection can cross
/// paragraphs and list items. GFM pipe tables are isolated because MarkdownUI's
/// grid is the authoritative table renderer and intentionally owns one native
/// selection surface per cell. Fenced code blocks are isolated so they can
/// scroll horizontally instead of wrapping inside the prose text view.
public enum SelectableMarkdownSection: Equatable, Sendable {
    case prose(String)
    case table(String)
    /// A fenced code block's body with the fence's indentation removed.
    /// `depth` is how many list items it is nested in (0 at top level), so
    /// the box can line up with the text of the item that owns it.
    case code(String, depth: Int)
}

public enum SelectableMarkdownSections {
    public static func split(_ markdown: String) -> [SelectableMarkdownSection] {
        guard !markdown.isEmpty else { return [] }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [SelectableMarkdownSection] = []
        var proseStart = lines.startIndex
        var listColumns: [Int] = []
        var index = lines.startIndex

        while index < lines.count {
            let line = lines[index]
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if !isBlank {
                // A line leaves every list item whose content column it sits
                // left of. (Lazy continuation lines are not modelled.)
                let indent = leadingSpaceCount(line)
                listColumns.removeAll { $0 > indent }
            }

            if let fence = opensFence(line, listColumns: listColumns) {
                appendProse(lines[proseStart..<index], to: &sections)
                var end = index + 1
                while end < lines.count, !closesFence(lines[end], fence: fence) {
                    end += 1
                }
                let body = lines[(index + 1)..<end]
                    .map { dropLeadingSpaces($0, upTo: fence.indent) }
                    .joined(separator: "\n")
                let depth = listColumns.filter { $0 <= fence.indent }.count
                sections.append(.code(body, depth: depth))
                index = min(end + 1, lines.count)
                proseStart = index
                continue
            }

            if index + 1 < lines.count, isTableHeader(line, delimiter: lines[index + 1]) {
                var end = index + 2
                while end < lines.count, isTableBodyRow(lines[end]) {
                    end += 1
                }
                appendProse(lines[proseStart..<index], to: &sections)
                sections.append(.table(lines[index..<end].joined(separator: "\n")))
                index = end
                proseStart = index
                continue
            }

            if !isBlank, let column = listItemContentColumn(line) {
                listColumns.append(column)
            }
            index += 1
        }

        guard !sections.isEmpty else { return [.prose(markdown)] }
        appendProse(lines[proseStart..<lines.endIndex], to: &sections)
        return sections
    }

    private struct Fence {
        let marker: Character
        let length: Int
        /// Leading spaces before the opening fence.
        let indent: Int
    }

    private static func appendProse(
        _ slice: ArraySlice<String>,
        to sections: inout [SelectableMarkdownSection]
    ) {
        var lower = slice.startIndex
        var upper = slice.endIndex
        while lower < upper, slice[lower].trimmingCharacters(in: .whitespaces).isEmpty {
            lower += 1
        }
        while upper > lower,
              slice[slice.index(before: upper)].trimmingCharacters(in: .whitespaces).isEmpty {
            upper -= 1
        }
        guard lower < upper else { return }
        sections.append(.prose(slice[lower..<upper].joined(separator: "\n")))
    }

    private static func isTableHeader(_ header: String, delimiter: String) -> Bool {
        guard leadingSpaceCount(header) <= 3,
              leadingSpaceCount(delimiter) <= 3,
              let headerCells = pipeCells(in: header),
              let delimiterCells = pipeCells(in: delimiter),
              !headerCells.isEmpty,
              headerCells.count == delimiterCells.count else {
            return false
        }
        return delimiterCells.allSatisfy(isDelimiterCell)
    }

    private static func isTableBodyRow(_ line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
              leadingSpaceCount(line) <= 3 else {
            return false
        }
        return pipeCells(in: line) != nil
    }

    /// Splits unescaped pipes and removes the optional outer pipe markers.
    /// Returns nil when the line has no actual column separator.
    private static func pipeCells(in line: String) -> [String]? {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        var cells = [""]
        var escaped = false
        var sawPipe = false

        for character in value {
            if character == "|", !escaped {
                cells.append("")
                sawPipe = true
            } else {
                cells[cells.count - 1].append(character)
            }

            if character == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
        }

        guard sawPipe else { return nil }
        if value.first == "|" { cells.removeFirst() }
        if hasUnescapedTrailingPipe(value), !cells.isEmpty { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func hasUnescapedTrailingPipe(_ value: String) -> Bool {
        guard value.last == "|" else { return false }
        var backslashes = 0
        var index = value.index(before: value.endIndex)
        while index > value.startIndex {
            let previous = value.index(before: index)
            guard value[previous] == "\\" else { break }
            backslashes += 1
            index = previous
        }
        return backslashes.isMultiple(of: 2)
    }

    private static func isDelimiterCell(_ cell: String) -> Bool {
        var value = cell[...]
        if value.first == ":" { value = value.dropFirst() }
        if value.last == ":" { value = value.dropLast() }
        return value.count >= 3 && value.allSatisfy { $0 == "-" }
    }

    /// A fence may sit up to three spaces past the content column of the
    /// list item it belongs to (or the margin, outside any list); deeper than
    /// that it is indented-code text, not a fence.
    private static func opensFence(_ line: String, listColumns: [Int]) -> Fence? {
        let indent = leadingSpaceCount(line)
        let container = listColumns.last { $0 <= indent } ?? 0
        guard indent - container <= 3 else { return nil }
        let trimmed = line.dropFirst(indent)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        // A backtick fence's info string may not contain a backtick
        // (otherwise the line is inline code, e.g. ```not a fence```).
        if marker == "`", trimmed.dropFirst(length).contains("`") { return nil }
        return Fence(marker: marker, length: length, indent: indent)
    }

    private static func closesFence(_ line: String, fence: Fence) -> Bool {
        guard leadingSpaceCount(line) <= fence.indent + 3 else { return false }
        let trimmed = line.drop(while: { $0 == " " })
        let markerRun = trimmed.prefix(while: { $0 == fence.marker })
        guard markerRun.count >= fence.length else { return false }
        return trimmed.dropFirst(markerRun.count).allSatisfy { $0.isWhitespace }
    }

    /// Column where a list item's content starts (`- `, `* `, `+ `, `1. `,
    /// `1) `), or nil when the line is not a list item.
    private static func listItemContentColumn(_ line: String) -> Int? {
        let indent = leadingSpaceCount(line)
        let rest = line.dropFirst(indent)
        let markerLength: Int
        if let first = rest.first, first == "-" || first == "*" || first == "+" {
            markerLength = 1
        } else {
            let digits = rest.prefix(while: { $0.isASCII && $0.isNumber }).count
            guard (1...9).contains(digits),
                  let delimiter = rest.dropFirst(digits).first,
                  delimiter == "." || delimiter == ")" else { return nil }
            markerLength = digits + 1
        }
        let afterMarker = rest.dropFirst(markerLength)
        let spaces = afterMarker.prefix(while: { $0 == " " }).count
        guard spaces > 0, spaces < afterMarker.count else { return nil }
        // Five or more spaces after the marker start indented code; the
        // content column is then one space past the marker.
        return indent + markerLength + (spaces >= 5 ? 1 : spaces)
    }

    private static func dropLeadingSpaces(_ line: String, upTo count: Int) -> String {
        String(line.dropFirst(min(count, leadingSpaceCount(line))))
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }
}

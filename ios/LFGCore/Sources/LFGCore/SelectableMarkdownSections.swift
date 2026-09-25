import Foundation

/// Rendering boundary for assistant Markdown.
///
/// Contiguous prose stays in one native text view so selection can cross
/// paragraphs and list items. GFM pipe tables are isolated because MarkdownUI's
/// grid is the authoritative table renderer and intentionally owns one native
/// selection surface per cell.
public enum SelectableMarkdownSection: Equatable, Sendable {
    case prose(String)
    case table(String)
}

public enum SelectableMarkdownSections {
    public static func split(_ markdown: String) -> [SelectableMarkdownSection] {
        guard !markdown.isEmpty else { return [] }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let tableRanges = findTableRanges(in: lines)
        guard !tableRanges.isEmpty else { return [.prose(markdown)] }

        var sections: [SelectableMarkdownSection] = []
        var cursor = lines.startIndex

        for tableRange in tableRanges {
            appendProse(lines[cursor..<tableRange.lowerBound], to: &sections)
            sections.append(.table(lines[tableRange].joined(separator: "\n")))
            cursor = tableRange.upperBound
        }
        appendProse(lines[cursor..<lines.endIndex], to: &sections)
        return sections
    }

    private struct Fence {
        let marker: Character
        let length: Int
    }

    private static func findTableRanges(in lines: [String]) -> [Range<Int>] {
        guard lines.count >= 2 else { return [] }

        var ranges: [Range<Int>] = []
        var fence: Fence?
        var index = 0

        while index < lines.count {
            if let activeFence = fence {
                if closesFence(lines[index], fence: activeFence) { fence = nil }
                index += 1
                continue
            }

            if let openingFence = opensFence(lines[index]) {
                fence = openingFence
                index += 1
                continue
            }

            guard index + 1 < lines.count,
                  isTableHeader(lines[index], delimiter: lines[index + 1]) else {
                index += 1
                continue
            }

            var end = index + 2
            while end < lines.count, isTableBodyRow(lines[end]) {
                end += 1
            }
            ranges.append(index..<end)
            index = end
        }

        return ranges
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

    private static func opensFence(_ line: String) -> Fence? {
        guard leadingSpaceCount(line) <= 3 else { return nil }
        let trimmed = line.drop(while: { $0 == " " })
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        return Fence(marker: marker, length: length)
    }

    private static func closesFence(_ line: String, fence: Fence) -> Bool {
        guard leadingSpaceCount(line) <= 3 else { return false }
        let trimmed = line.drop(while: { $0 == " " })
        let markerRun = trimmed.prefix(while: { $0 == fence.marker })
        guard markerRun.count >= fence.length else { return false }
        return trimmed.dropFirst(markerRun.count).allSatisfy { $0.isWhitespace }
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }
}

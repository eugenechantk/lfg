import SwiftUI
import UIKit
import LFGCore

// MARK: - Selectable prose (in-place native text selection)

/// A transcript message rendered in ONE non-scrolling `UITextView`, so the
/// reader gets UIKit's own selection on the transcript itself: long-press for
/// the cursor + magnifier, drag to extend, handles, and the system edit menu
/// (Copy · Look Up · Translate · Share). One text view per contiguous prose
/// section means a drag can run across paragraphs and list items. Tables stay
/// in MarkdownUI's grid and intentionally keep one selection surface per cell.
///
/// Structure comes from `SelectableText` (LFGCore); `SelectableTextRenderer`
/// turns it into an attributed string; `ProseTextView` draws table gridlines
/// and code-block backgrounds beneath the text.
struct SelectableProseView: UIViewRepresentable {
    enum Content: Equatable {
        /// GFM markdown (assistant replies).
        case markdown(String)
        /// Verbatim text, no markdown interpretation (user bubbles).
        case plain(String)
        /// A fenced code block's body: monospaced, unwrapped, hugs its width
        /// (MarkdownUI supplies the box and the horizontal scroll).
        case code(String)
    }

    let content: Content
    var palette: SelectableTextRenderer.Palette = .standard
    /// Report the text's natural width instead of the proposal (a chat bubble
    /// hugs a short line; a full-width reply doesn't).
    var hugsContent = false
    /// Semibold base weight (table header row).
    var semibold = false
    /// Fired on a single tap that is not on a link; the text view would
    /// otherwise swallow the tap before a SwiftUI `onTapGesture` sees it.
    var onTap: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    init(markdown: String, palette: SelectableTextRenderer.Palette = .standard, semibold: Bool = false, onTap: (() -> Void)? = nil) {
        self.content = .markdown(markdown)
        self.palette = palette
        self.semibold = semibold
        self.onTap = onTap
    }

    init(code: String) {
        self.content = .code(code)
        self.hugsContent = true
    }

    init(plain: String, palette: SelectableTextRenderer.Palette = .standard, hugsContent: Bool = false, onTap: (() -> Void)? = nil) {
        self.content = .plain(plain)
        self.palette = palette
        self.hugsContent = hugsContent
        self.onTap = onTap
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProseTextView {
        let view = ProseTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.isOpaque = false
        view.contentMode = .redraw
        view.dataDetectorTypes = []
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.linkTextAttributes = [.foregroundColor: palette.link, .underlineStyle: palette.linkUnderline ? NSUnderlineStyle.single.rawValue : 0]
        view.tintColor = palette.tint
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "selectableProse"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.openURL = openURL
        context.coordinator.onTap = onTap
        if onTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = context.coordinator
            view.addGestureRecognizer(tap)
        }
        return view
    }

    func updateUIView(_ uiView: ProseTextView, context: Context) {
        context.coordinator.openURL = openURL
        context.coordinator.onTap = onTap
        uiView.tintColor = palette.tint
        // SwiftUI calls update before the first size proposal. Rendering at a
        // made-up 10,000pt width here used to build every attributed string once,
        // then immediately throw it away and build it again at the real width in
        // `sizeThatFits`. Defer the first render until we have an actual proposal;
        // later updates reuse the last measured width.
        if let width = context.coordinator.renderedWidth {
            context.coordinator.render(
                content,
                palette: palette,
                semibold: semibold,
                into: uiView,
                width: width
            )
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProseTextView, context: Context) -> CGSize? {
        // A concrete width is the only proposal a paragraph can answer; for
        // `.unspecified` lay out at a generous width and report the natural size.
        let width = proposal.width.map { $0.isFinite && $0 > 0 ? $0 : 10_000 } ?? 10_000
        context.coordinator.render(content, palette: palette, semibold: semibold, into: uiView, width: width)
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // An unspecified width is a request for the ideal size (a `Layout`
        // measuring a table cell, a horizontal ScrollView): answer with the
        // natural unwrapped width, not the 10_000pt scratch width.
        if hugsContent || proposal.width == nil {
            // Natural single-line width, capped at the proposal; re-fit at that
            // width so the height matches what will be laid out.
            let natural = ceil(uiView.sizeThatFits(CGSize(width: 10_000, height: CGFloat.greatestFiniteMagnitude)).width) + 1
            let hugged = min(width, natural)
            let refit = uiView.sizeThatFits(CGSize(width: hugged, height: .greatestFiniteMagnitude))
            return CGSize(width: hugged, height: ceil(refit.height))
        }
        return CGSize(width: proposal.width ?? fitted.width, height: ceil(fitted.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var openURL: OpenURLAction?
        var onTap: (() -> Void)?
        private var renderedContent: Content?
        private var renderedPaletteID: String?
        private var renderedSemibold = false
        private(set) var renderedWidth: CGFloat?
        private var rendered: NSAttributedString?
        private var parsedMarkdown: (source: String, blocks: [SelectableText.Block])?
        private var renderedDependsOnWidth = false

        /// Renders only when the inputs changed. Width matters because table
        /// columns are measured against it.
        func render(_ content: Content, palette: SelectableTextRenderer.Palette, semibold: Bool, into view: ProseTextView, width: CGFloat) {
            let sameInputs = renderedContent == content
                && renderedPaletteID == palette.id
                && renderedSemibold == semibold
                && rendered != nil
            let sameWidth = renderedWidth.map { abs($0 - width) < 0.5 } ?? false

            // Paragraphs, code blocks and user bubbles lay out their existing
            // attributed string at the proposed UITextView width. Whole-message
            // tables bake column widths into attributes and must rebuild when
            // that width changes.
            if sameInputs && (!renderedDependsOnWidth || sameWidth) {
                renderedWidth = width
                return
            }

            let string: NSAttributedString
            switch content {
            case .markdown(let md):
                let blocks: [SelectableText.Block]
                if let parsedMarkdown, parsedMarkdown.source == md {
                    blocks = parsedMarkdown.blocks
                } else {
                    blocks = SelectableText.parse(markdown: md)
                    parsedMarkdown = (md, blocks)
                }
                renderedDependsOnWidth = blocks.contains { block in
                    if case .table = block { return true }
                    return false
                }
                view.drawsBlockDecorations = blocks.contains { block in
                    switch block {
                    case .table, .codeBlock: true
                    default: false
                    }
                }
                string = SelectableTextRenderer.render(blocks: blocks, palette: palette, availableWidth: width, semibold: semibold)
            case .plain(let text):
                parsedMarkdown = nil
                renderedDependsOnWidth = false
                view.drawsBlockDecorations = false
                let blocks: [SelectableText.Block] = text.isEmpty ? [] : [.paragraph(spans: [.init(text: text)], depth: 0, marker: nil, quoted: false)]
                string = SelectableTextRenderer.render(blocks: blocks, palette: palette, availableWidth: width, semibold: semibold)
            case .code(let code):
                parsedMarkdown = nil
                renderedDependsOnWidth = false
                // MarkdownUI owns the code-block background for this per-block
                // path, so the text view has no custom decorations to enumerate.
                view.drawsBlockDecorations = false
                string = SelectableTextRenderer.renderCode(code, palette: palette)
            }
            renderedContent = content
            renderedPaletteID = palette.id
            renderedSemibold = semibold
            renderedWidth = width
            rendered = string
            view.attributedText = string
            view.setNeedsDisplay()
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view as? UITextView else { return }
            // Let link taps go to the text view's own handling.
            let point = recognizer.location(in: view)
            if let position = view.closestPosition(to: point),
               let range = view.tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: .layout(.left)),
               view.textStyling(at: range.start, in: .forward)?[.link] != nil {
                return
            }
            // A tap while a selection is showing clears it (UIKit behaviour) — don't
            // also toggle chrome on that tap.
            if view.selectedRange.length > 0 { return }
            onTap?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content, let openURL {
                return UIAction { _ in openURL(url) }
            }
            return defaultAction
        }
    }
}

/// `UITextView` that paints block decorations — table gridlines and row
/// stripes, code-block boxes — under the text, from custom attributes the
/// renderer stamps on paragraphs. Drawn in `draw(_:)`, which sits beneath the
/// text container subview, so selection highlights still render above.
final class ProseTextView: UITextView {
    /// The shipping MarkdownUI path supplies its own table/code chrome. Most
    /// instances are therefore plain paragraph text views and can skip the
    /// TextKit fragment walk in `draw(_:)` entirely. This remains enabled for
    /// the older whole-message renderer retained by the debug fixture.
    var drawsBlockDecorations = false {
        didSet {
            if drawsBlockDecorations != oldValue { setNeedsDisplay() }
        }
    }

    override var bounds: CGRect {
        didSet { if bounds.size != oldValue.size { setNeedsDisplay() } }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        // `layoutSubviews` can run repeatedly while the outer transcript is
        // placing lazy rows. It must not invalidate every paragraph and then
        // force TextKit to ensure + enumerate the whole document on the next
        // frame. Content changes and real bounds-size changes already invalidate.
        guard drawsBlockDecorations,
              let layout = textLayoutManager,
              let storage = layout.textContentManager as? NSTextContentStorage,
              let text = storage.textStorage, text.length > 0,
              let context = UIGraphicsGetCurrentContext() else { return }
        layout.ensureLayout(for: layout.documentRange)

        var codeBoxes: [(id: Int, rect: CGRect)] = []
        let inset = textContainerInset
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            guard let element = fragment.textElement, let elementRange = element.elementRange else { return true }
            let location = storage.offset(from: layout.documentRange.location, to: elementRange.location)
            guard location >= 0, location < text.length else { return true }
            let attrs = text.attributes(at: location, effectiveRange: nil)
            guard let kind = attrs[.lfgBlockKind] as? String else { return true }
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: inset.left, dy: inset.top)

            switch kind {
            case SelectableTextRenderer.BlockKind.tableHeader, SelectableTextRenderer.BlockKind.tableRow:
                let width = (attrs[.lfgTableWidth] as? CGFloat) ?? frame.width
                let rowRect = CGRect(x: frame.minX, y: frame.minY, width: min(width, frame.width), height: frame.height)
                let isHeader = kind == SelectableTextRenderer.BlockKind.tableHeader
                let rowIndex = (attrs[.lfgTableRowIndex] as? Int) ?? 0
                if isHeader {
                    context.setFillColor(UIColor.tertiarySystemFill.cgColor)
                    context.fill(rowRect)
                } else if rowIndex % 2 == 0 {
                    context.setFillColor(UIColor.secondarySystemBackground.cgColor)
                    context.fill(rowRect)
                }
                context.setStrokeColor(UIColor.separator.cgColor)
                let hairline = 1 / max(1, self.traitCollection.displayScale)
                context.setLineWidth(hairline)
                var lines: [CGPoint] = []
                // Horizontal: top of header, bottom of every row.
                if isHeader {
                    lines += [CGPoint(x: rowRect.minX, y: rowRect.minY), CGPoint(x: rowRect.maxX, y: rowRect.minY)]
                }
                lines += [CGPoint(x: rowRect.minX, y: rowRect.maxY), CGPoint(x: rowRect.maxX, y: rowRect.maxY)]
                // Vertical: left edge, each column boundary, right edge.
                var xs: [CGFloat] = [rowRect.minX, rowRect.maxX]
                if let style = attrs[.paragraphStyle] as? NSParagraphStyle {
                    xs += style.tabStops.map { frame.minX + $0.location - SelectableTextRenderer.tableCellInset }
                }
                for x in xs where x <= rowRect.maxX + 0.5 {
                    lines += [CGPoint(x: x, y: rowRect.minY), CGPoint(x: x, y: rowRect.maxY)]
                }
                context.strokeLineSegments(between: lines)
            case SelectableTextRenderer.BlockKind.codeBlock:
                let id = (attrs[.lfgBlockID] as? Int) ?? -1
                if let last = codeBoxes.indices.last, codeBoxes[last].id == id {
                    codeBoxes[last].rect = codeBoxes[last].rect.union(frame)
                } else {
                    codeBoxes.append((id, frame))
                }
            default:
                break
            }
            return true
        }

        for box in codeBoxes {
            let rect = CGRect(x: box.rect.minX, y: box.rect.minY, width: box.rect.width, height: box.rect.height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            context.setFillColor(UIColor.secondarySystemBackground.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }
}

extension NSAttributedString.Key {
    static let lfgBlockKind = NSAttributedString.Key("lfg.blockKind")
    static let lfgBlockID = NSAttributedString.Key("lfg.blockID")
    static let lfgTableWidth = NSAttributedString.Key("lfg.tableWidth")
    static let lfgTableRowIndex = NSAttributedString.Key("lfg.tableRowIndex")
}

// MARK: - Renderer

/// Turns `SelectableText` blocks into the attributed string a `ProseTextView`
/// shows. Structure comes from LFGCore; only fonts, colours, spacing and the
/// decoration attributes live here.
enum SelectableTextRenderer {
    typealias Block = SelectableText.Block
    typealias Span = SelectableText.Span

    enum BlockKind {
        static let tableHeader = "tableHeader"
        static let tableRow = "tableRow"
        static let codeBlock = "codeBlock"
    }

    struct Palette {
        var id: String
        var text: UIColor
        var secondary: UIColor
        var link: UIColor
        var linkUnderline: Bool
        var tint: UIColor?
        var inlineCodeBackground: UIColor
        var rule: UIColor

        /// Assistant prose on the page background.
        static let standard = Palette(
            id: "standard", text: .label, secondary: .secondaryLabel, link: .tintColor,
            linkUnderline: false, tint: nil, inlineCodeBackground: .secondarySystemBackground, rule: .tertiaryLabel
        )
        /// White text on the accent-coloured user bubble.
        static let onAccent = Palette(
            id: "onAccent", text: .white, secondary: UIColor.white.withAlphaComponent(0.85), link: .white,
            linkUnderline: true, tint: .white, inlineCodeBackground: UIColor.white.withAlphaComponent(0.22),
            rule: UIColor.white.withAlphaComponent(0.5)
        )
    }

    static let listIndent: CGFloat = 22
    static let tableCellInset: CGFloat = 8
    static let tableCellPadding: CGFloat = 20
    static let tableColumnMinWidth: CGFloat = 44
    static let codeBlockInset: CGFloat = 10

    static func render(blocks: [Block], palette: Palette, availableWidth: CGFloat, semibold: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var blockID = 0
        let base = semibold ? withTraits(body, [.traitBold]) : body
        for (index, block) in blocks.enumerated() {
            let next = index + 1 < blocks.count ? blocks[index + 1] : nil
            let previous = index > 0 ? blocks[index - 1] : nil
            blockID += 1
            out.append(render(block, id: blockID, previous: previous, next: next, palette: palette, availableWidth: availableWidth, base: base))
            if next != nil { out.append(NSAttributedString(string: "\n")) }
        }
        return out
    }

    /// A fenced code block's body, matching MarkdownUI's GitHub theme (0.85em
    /// monospaced, 0.225em line spacing). No wrapping — the caller scrolls.
    static func renderCode(_ code: String, palette: Palette) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = bodyPointSize * 0.225
        style.lineBreakMode = .byClipping
        return NSAttributedString(string: code, attributes: [
            .font: mono,
            .foregroundColor: palette.text,
            .paragraphStyle: style,
        ])
    }

    // MARK: Fonts — sized to match `Theme.gitHub` (16pt body, 0.85em code).

    private static let bodyPointSize: CGFloat = 16

    /// Height of one body line in a `ProseTextView` (zero insets), so a list
    /// marker can be centred on the first line of a paragraph it sits beside.
    static var firstLineHeight: CGFloat { body.lineHeight }


    private static var body: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: bodyPointSize))
    }

    private static var mono: UIFont {
        UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: bodyPointSize * 0.85, weight: .regular))
    }

    private static func headingFont(level: Int) -> UIFont {
        let style: UIFont.TextStyle
        switch level {
        case 1: style = .title2
        case 2: style = .title3
        default: style = .headline
        }
        return withTraits(.preferredFont(forTextStyle: style), [.traitBold])
    }

    private static func withTraits(_ font: UIFont, _ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(
            font.fontDescriptor.symbolicTraits.union(traits)
        ) else { return font }
        return UIFont(descriptor: descriptor, size: 0)
    }

    // MARK: Blocks

    private static func render(
        _ block: Block, id: Int, previous: Block?, next: Block?, palette: Palette, availableWidth: CGFloat, base: UIFont
    ) -> NSAttributedString {
        switch block {
        case .paragraph(let spans, let depth, let marker, let quoted):
            return paragraph(spans, depth: depth, marker: marker, quoted: quoted, previous: previous, next: next, palette: palette, base: base)
        case .heading(let level, let spans):
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 8
            style.paragraphSpacingBefore = previous == nil ? 0 : 10
            return inline(spans, base: headingFont(level: level), color: palette.text, paragraphStyle: style, palette: palette)
        case .codeBlock(let code):
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 10
            style.paragraphSpacingBefore = 10
            style.firstLineHeadIndent = codeBlockInset
            style.headIndent = codeBlockInset
            style.tailIndent = -codeBlockInset
            style.lineBreakMode = .byCharWrapping
            return NSAttributedString(string: code, attributes: [
                .font: mono,
                .foregroundColor: palette.text,
                .paragraphStyle: style,
                .lfgBlockKind: BlockKind.codeBlock,
                .lfgBlockID: id,
            ])
        case .table(let header, let rows):
            return table(header: header, rows: rows, id: id, palette: palette, availableWidth: availableWidth)
        case .rule:
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 12
            style.paragraphSpacingBefore = 4
            return NSAttributedString(string: "———", attributes: [
                .font: body,
                .foregroundColor: palette.rule,
                .paragraphStyle: style,
            ])
        }
    }

    private static func isListItem(_ block: Block?) -> Bool {
        if case .paragraph(_, let depth, _, _)? = block { return depth > 0 }
        return false
    }

    private static func paragraph(
        _ spans: [Span], depth: Int, marker: String?, quoted: Bool, previous: Block?, next: Block?, palette: Palette, base: UIFont
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        // GitHub theme: relativeLineSpacing(.em(0.25)).
        style.lineSpacing = bodyPointSize * 0.25
        let color: UIColor = quoted ? palette.secondary : palette.text
        let result = NSMutableAttributedString()

        if depth > 0 {
            // Marker sits at the previous level's indent; wrapped lines align
            // with the text after it via the tab stop.
            let markerIndent = listIndent * CGFloat(depth - 1)
            let textIndent = listIndent * CGFloat(depth)
            style.firstLineHeadIndent = markerIndent
            style.headIndent = textIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: textIndent)]
            style.defaultTabInterval = listIndent
            style.paragraphSpacing = isListItem(next) ? 3 : 12
            style.paragraphSpacingBefore = isListItem(previous) ? 0 : 4
            if let marker {
                result.append(NSAttributedString(string: "\(marker)\t", attributes: [
                    .font: body, .foregroundColor: color, .paragraphStyle: style,
                ]))
            } else {
                style.firstLineHeadIndent = textIndent
            }
        } else if quoted {
            style.firstLineHeadIndent = 16
            style.headIndent = 16
            style.paragraphSpacing = 12
        } else {
            style.paragraphSpacing = next == nil ? 0 : 12
        }

        result.append(inline(spans, base: base, color: color, paragraphStyle: style, palette: palette))
        return result
    }

    private static func table(
        header: [[Span]], rows: [[[Span]]], id: Int, palette: Palette, availableWidth: CGFloat
    ) -> NSAttributedString {
        let allRows = [header] + rows
        let columnCount = allRows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return NSAttributedString() }

        // Measure each column at its widest cell, then shrink proportionally
        // if the natural grid is wider than the message; a cell that no longer
        // fits wraps inside its column instead of breaking the row.
        var widths = Array(repeating: tableColumnMinWidth, count: columnCount)
        for (rowIndex, row) in allRows.enumerated() {
            let font = rowIndex == 0 ? withTraits(body, [.traitBold]) : body
            for (column, cell) in row.enumerated() where column < columnCount {
                let text = cell.map(\.text).joined()
                let width = (text as NSString).size(withAttributes: [.font: font]).width + tableCellPadding
                widths[column] = max(widths[column], ceil(width))
            }
        }
        let natural = widths.reduce(0, +)
        let maxWidth = max(availableWidth, tableColumnMinWidth * CGFloat(columnCount))
        if natural > maxWidth {
            let scale = maxWidth / natural
            widths = widths.map { max(tableColumnMinWidth, floor($0 * scale)) }
        }
        let tableWidth = widths.reduce(0, +)

        var stops: [NSTextTab] = []
        var location: CGFloat = tableCellInset
        for width in widths.dropLast() {
            location += width
            stops.append(NSTextTab(textAlignment: .left, location: location))
        }

        let result = NSMutableAttributedString()
        for (rowIndex, row) in allRows.enumerated() {
            let isHeader = rowIndex == 0
            let isLast = rowIndex == allRows.count - 1
            let style = NSMutableParagraphStyle()
            style.tabStops = stops
            style.defaultTabInterval = tableColumnMinWidth
            style.firstLineHeadIndent = tableCellInset
            style.headIndent = tableCellInset
            style.tailIndent = tableWidth - tableCellInset
            style.lineBreakMode = .byWordWrapping
            style.paragraphSpacingBefore = 6
            // Rows keep 6pt inside the grid; the last row also carries the
            // gap before the next block (the fill only covers the fragment).
            style.paragraphSpacing = isLast ? 12 : 6
            let font = isHeader ? withTraits(body, [.traitBold]) : body
            var rowAttributes: [NSAttributedString.Key: Any] = [
                .lfgBlockKind: isHeader ? BlockKind.tableHeader : BlockKind.tableRow,
                .lfgBlockID: id,
                .lfgTableWidth: tableWidth,
                .lfgTableRowIndex: rowIndex,
            ]
            rowAttributes[.paragraphStyle] = style

            let line = NSMutableAttributedString()
            for column in 0..<columnCount {
                if column > 0 {
                    line.append(NSAttributedString(string: "\t", attributes: [
                        .font: font, .foregroundColor: palette.text, .paragraphStyle: style,
                    ]))
                }
                let cell = column < row.count ? row[column] : []
                line.append(inline(cell, base: font, color: palette.text, paragraphStyle: style, palette: palette))
            }
            line.addAttributes(rowAttributes, range: NSRange(location: 0, length: line.length))
            result.append(line)
            if !isLast { result.append(NSAttributedString(string: "\n", attributes: rowAttributes)) }
        }
        return result
    }

    // MARK: Inline

    private static func inline(
        _ spans: [Span], base: UIFont, color: UIColor, paragraphStyle: NSParagraphStyle, palette: Palette
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in spans {
            var font = span.code ? mono : base
            var traits: UIFontDescriptor.SymbolicTraits = []
            if span.bold { traits.insert(.traitBold) }
            if span.italic { traits.insert(.traitItalic) }
            if !traits.isEmpty { font = withTraits(font, traits) }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
            if span.code {
                attributes[.backgroundColor] = palette.inlineCodeBackground
            }
            if span.strikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = span.link {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: span.text, attributes: attributes))
        }
        return result
    }
}

// MARK: - Debug fixture

#if DEBUG
/// Launch with `LFG_SELECT_TEXT_FIXTURE=1`: a two-message transcript through
/// the real `TranscriptMessageView` path, with a markdown-rich assistant reply
/// that includes a table, plus a text field to prove copies via the pasteboard.
struct SelectTextFixture: View {
    static let assistantMarkdown = """
    ## Deploy summary

    The **staging** build is live. Run `lfg serve --port 8766` to check it, or read the [runbook](https://example.com/runbook).

    | Host | Port | Status |
    |------|-----:|--------|
    | eugenes-macbook-pro | 8766 | healthy |
    | eugenes-macbook-air | 8766 | *degraded* |

    Next steps:

    - Restart the Air's server
      - confirm `tmux` resolves on PATH
    - Re-run the smoke test

    1. Pull main
    2. Build

    ```sh
    ssh eugenechan@eugenes-macbook-air 'scripts/serve-forever.sh'
    ```

    > Do not restart the Pro; it owns the tunnel.

    A closing paragraph long enough to wrap onto a second line so a drag can cross a line break as well as a block boundary.
    """

    @State private var pasted = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TranscriptMessageView(message: SessionMessage(
                    id: "fixture-user", role: "user", kind: "text",
                    text: "What's the state of the hosts?", ts: 1_788_700_000_000
                ))
                TranscriptMessageView(message: SessionMessage(
                    id: "fixture-assistant", role: "assistant", kind: "text",
                    text: Self.assistantMarkdown, ts: 1_788_700_010_000
                ))
                TextField("Paste here to verify the pasteboard", text: $pasted, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .padding(.top, 24)
                    .accessibilityIdentifier("fixturePasteField")
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle("Select text fixture")
        .accessibilityIdentifier("selectTextFixture")
    }
}
#endif

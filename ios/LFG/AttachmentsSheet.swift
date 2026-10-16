import SwiftUI
import LFGCore

/// Everything a session produced, in one place (S2 board `s2-files`).
///
/// The transcript renders attachments where they were mentioned, which is right
/// for reading but wrong for retrieval — the chart an agent made two hours and
/// four hundred tool calls ago is somewhere up there, and scrolling is the only
/// way back to it. This is that same parse, flattened: files in three sections
/// (Images, Videos, Documents) as plain rows with no previews, links on their
/// own tab, each opening exactly what the inline card would have opened.
struct AttachmentsSheet: View {
    let messages: [SessionMessage]
    var cwd: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hostFiles) private var hostFiles
    @Environment(\.openURL) private var openURL

    @State private var resources: TranscriptResources?
    @State private var viewing: MediaRef?
    @State private var showingLinks = false

    var body: some View {
        let model = resources.map { FilesSheetModel($0, cwd: cwd, nowMs: Date().timeIntervalSince1970 * 1_000) }
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.top, 20)
            if let model {
                tabs(model)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if showingLinks { links(model) } else { files(model) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .padding(.top, 14)
            } else {
                // Only visible on a very long transcript; the parse is fast.
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(S2.surface.ignoresSafeArea())
        .accessibilityIdentifier("attachmentsSheet")
        // Recompute when the session appends — a live agent adds files while
        // this is open, and a stale list is worse than a slow one.
        .task(id: messages.count) {
            let snapshot = messages
            resources = await Task.detached { TranscriptResourceIndex.collect(from: snapshot) }.value
        }
        .sheet(item: $viewing) { ref in
            FileViewerSheet(
                ref: ref,
                files: resources?.files.map(\.ref) ?? [ref],
                hostFiles: hostFiles
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Files & links")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(S2.white)
                    .cssLineBox(size: 22, lineHeight: 28)
                Text("Shared in this session")
                    .font(.system(size: 14))
                    .foregroundStyle(S2.secondaryInk)
                    .frame(height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
                SheetGlyph(kind: .close)
                    .stroke(SessionSheet.chromeInk, style: StrokeStyle(lineWidth: 2.8 * 14 / 24, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(S2.chip))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("attachmentsClose")
        }
    }

    /// "Files 5 · Links 2", a pill switch (board: 34pt, the selected half lighter).
    private func tabs(_ model: FilesSheetModel) -> some View {
        HStack(spacing: 0) {
            tab("Files \(model.fileCount)", selected: !showingLinks) { showingLinks = false }
            tab("Links \(model.links.count)", selected: showingLinks) { showingLinks = true }
        }
        .padding(2)
        .background(Capsule().fill(S2.chip))
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(S2.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if selected { Capsule().fill(SessionSheet.segmentSelected) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("attachmentsTab-\(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func files(_ model: FilesSheetModel) -> some View {
        if model.sections.isEmpty {
            empty("Files this session shares will collect here.")
        }
        ForEach(model.sections) { entry in
            HStack(spacing: 6) {
                Text(entry.section.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(S2.secondaryInk)
                Text("\(entry.rows.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(S2.metaInk)
            }
            .padding(EdgeInsets(top: 10, leading: 20, bottom: 4, trailing: 20))
            .frame(height: 29, alignment: .bottom)
            ForEach(entry.rows) { row in
                Button { viewing = row.ref } label: {
                    resourceRow(glyph: FileGlyph(kind: glyphKind(entry.section)), title: row.title, meta: row.meta)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fileListRow_\(row.id)")
            }
        }
    }

    @ViewBuilder
    private func links(_ model: FilesSheetModel) -> some View {
        if model.links.isEmpty {
            empty("Links this session shares will collect here.")
        }
        ForEach(model.links) { row in
            Button {
                if let url = URL(string: row.url) { openURL(url) }
            } label: {
                linkRow(row)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("linkListRow_\(row.id)")
        }
    }

    private func resourceRow(glyph: FileGlyph, title: String, meta: String) -> some View {
        HStack(spacing: 12) {
            glyph
                .stroke(SessionSheet.chromeInk, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 24)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(S2.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .cssLineBox(size: 17, lineHeight: 22)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 13))
                            .foregroundStyle(S2.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(height: 15)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BoardGlyph(kind: .chevronRight, lineWidth: 3)
                    .foregroundStyle(S2.color(dark: 0x636366, light: 0xC7C7CC))
                    .frame(width: 11, height: 11)
            }
            .padding(.vertical, 10)
            .padding(.trailing, 16)
            .frame(height: 59)
            .overlay(alignment: .bottom) {
                // Board: `border-bottom: 0.5px solid #38383A`.
                Rectangle().fill(S2.surfaceBorder).frame(height: 0.5)
            }
        }
        .padding(.leading, 20)
        .contentShape(Rectangle())
    }

    /// Board `s2-files`, Links tab: the domain's letter on a 30pt tile, the
    /// link's title over its domain, and an arrow that says it leaves the app.
    private func linkRow(_ row: FilesSheetModel.LinkRow) -> some View {
        HStack(spacing: 12) {
            Text(row.initial)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(S2.chipInk)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(S2.chip))
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 17))
                        .foregroundStyle(S2.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .cssLineBox(size: 17, lineHeight: 22)
                    Text(row.meta)
                        .font(.system(size: 13))
                        .foregroundStyle(S2.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(height: 15)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FileGlyph(kind: .external)
                    .stroke(S2.color(dark: 0x636366, light: 0xC7C7CC),
                            style: StrokeStyle(lineWidth: 2.2 * 15 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 15, height: 15)
            }
            .padding(.vertical, 11)
            .padding(.trailing, 16)
            .frame(height: 61)
            .overlay(alignment: .bottom) {
                Rectangle().fill(S2.surfaceBorder).frame(height: 0.5)
            }
        }
        .padding(.leading, 20)
        .contentShape(Rectangle())
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(S2.secondaryInk)
            .padding(.horizontal, 20)
            .padding(.top, 10)
    }

    private func glyphKind(_ section: FilesSheetModel.Section) -> FileGlyph.Kind {
        switch section {
        case .images: return .image
        case .videos: return .video
        case .documents: return .document
        }
    }
}

/// The Files & links rows' icons, from the board's SVGs (24-unit box).
struct FileGlyph: Shape {
    enum Kind { case image, video, document, external }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        func line(_ points: [(CGFloat, CGFloat)], close: Bool = false) {
            guard let first = points.first else { return }
            path.move(to: p(first.0, first.1))
            for pt in points.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
            if close { path.closeSubpath() }
        }
        switch kind {
        case .image:
            line([(3, 4), (21, 4), (21, 20), (3, 20)], close: true)
            path.addEllipse(in: CGRect(x: rect.minX + 7 * k, y: rect.minY + 9 * k, width: 3 * k, height: 3 * k))
            line([(21, 16), (16, 11), (7, 20)])
        case .video:
            line([(3, 6), (15, 6), (15, 18), (3, 18)], close: true)
            line([(15, 10), (21, 7), (21, 17), (15, 14)])
        case .document:
            line([(6, 2.5), (14, 2.5), (18.5, 7), (18.5, 21.5), (6, 21.5)], close: true)
            line([(14, 2.5), (14, 7), (18.5, 7)])
            line([(9, 12), (15, 12)])
            line([(9, 16), (15, 16)])
        case .external:
            // M14 4h6v6 M20 4l-9 9 M18 14v6H4V6h6
            line([(14, 4), (20, 4), (20, 10)])
            line([(20, 4), (11, 13)])
            line([(18, 14), (18, 20), (4, 20), (4, 6), (10, 6)])
        }
        return path
    }
}

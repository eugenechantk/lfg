import SwiftUI
import AVKit
import PDFKit
import QuickLook
import MarkdownUI
import LFGCore

// MARK: - Host file URL resolution

/// Builds URLs against the connected host. Local absolute paths the agent emits
/// (e.g. /Users/…/out.png) are served through `GET /api/file?path=…`; http(s)
/// URLs pass through untouched.
struct HostFiles: Sendable {
    let client: LFGClient
    var baseURL: URL { client.baseURL }
    /// The session's working directory, used to resolve relative paths the agent
    /// emits in prose (e.g. `improvement-log/foo.md`) to a real host file. Nil
    /// outside a session, where only absolute paths can be served.
    var cwd: String? = nil

    func fileURL(forPath path: String) -> URL? {
        var c = URLComponents(url: baseURL.appendingPathComponent("api/file"), resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "path", value: path)]
        return c?.url
    }

    /// Turn a relative path into an absolute host path by joining the session cwd.
    private func absolutePath(_ path: String) -> String? {
        if path.hasPrefix("/") { return path }
        guard let cwd, !cwd.isEmpty else { return nil }
        return (cwd.hasSuffix("/") ? cwd : cwd + "/") + path
    }

    /// Resolve a URL parsed out of markdown/text to something loadable.
    func resolve(_ url: URL) -> URL? {
        if let s = url.scheme?.lowercased(), s == "http" || s == "https" { return url }
        let path = url.scheme == "file" ? url.path : url.absoluteString
        guard let abs = absolutePath(path) else { return nil }
        return fileURL(forPath: abs)
    }

    func resolve(rawPath: String) -> URL? {
        if rawPath.hasPrefix("http://") || rawPath.hasPrefix("https://") { return URL(string: rawPath) }
        guard let abs = absolutePath(rawPath) else { return nil }
        return fileURL(forPath: abs)
    }
}

private struct HostFilesKey: EnvironmentKey {
    static let defaultValue: HostFiles? = nil
}
extension EnvironmentValues {
    var hostFiles: HostFiles? {
        get { self[HostFilesKey.self] }
        set { self[HostFilesKey.self] = newValue }
    }
}

// `MediaKind`, `MediaRef`, `MediaScanner` and the whole-transcript index now
// live in LFGCore (`MediaRefs.swift`) — pure string parsing, covered by tests
// that run without a simulator. This file keeps only the SwiftUI surfaces.

// MARK: - Markdown prose

/// Gives MarkdownUI's `Grid` an ideal size measured at the same bounded width
/// used to render the cell. A flexible `frame(minWidth:maxWidth:)` clamps the
/// cell after its child reports an unwrapped ideal height, which can leave a
/// later multiline cell drawing through the rows below it.
private struct BoundedTableCellLayout: Layout {
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let width: CGFloat
        if let proposedWidth = proposal.width {
            if proposedWidth.isFinite {
                width = min(max(proposedWidth, minWidth), maxWidth)
            } else {
                width = maxWidth
            }
        } else {
            let idealWidth = subview.sizeThatFits(.unspecified).width
            width = min(max(idealWidth, minWidth), maxWidth)
        }

        let contentSize = subview.sizeThatFits(
            ProposedViewSize(width: width, height: proposal.height)
        )
        return CGSize(width: width, height: contentSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}

/// Marker and content top-aligned; see `Theme.lfgFlat`'s `.listItem`.
private struct TopAlignedListItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 4) {
            configuration.icon
                // Centre the marker on the first line of the item's text.
                .alignmentGuide(.top) { d in
                    d[VerticalAlignment.center] - SelectableTextRenderer.firstLineHeight / 2
                }
            configuration.title
        }
    }
}

extension MarkdownUI.Theme {
    /// GitHub styling, but with the body-text background container removed so the
    /// assistant response flows directly on the page (no gray box). Code blocks,
    /// inline code, headings, lists, tables keep their own styling.
    @MainActor
    static var lfgFlat: MarkdownUI.Theme {
        MarkdownUI.Theme.gitHub
            .text {
                ForegroundColor(.primary)
                BackgroundColor(.clear)
                FontSize(16)
            }
            // Paragraphs, code blocks and table cells render their text in a
            // native `UITextView` (`SelectableProseView`) so a long-press gives
            // the cursor + handles in place. Selection is scoped to the block —
            // one paragraph, one cell — which is what keeps MarkdownUI's own
            // layout (tables, lists, code chrome) exactly as it was.
            .paragraph { configuration in
                SelectableProseView(markdown: configuration.content.renderMarkdown())
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownMargin(top: 0, bottom: 16)
            }
            // A UIKit text view has no text baseline for SwiftUI, so the default
            // `Label` style centred the bullet on the whole item (wrong for an
            // item holding a nested list). Pin marker and content to the top.
            .listItem { configuration in
                configuration.label
                    .labelStyle(TopAlignedListItemLabelStyle())
                    .markdownMargin(top: .em(0.25))
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    SelectableProseView(code: configuration.content)
                        .padding(16)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: 0, bottom: 16)
            }
            .table { configuration in
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        // Keep readable column widths; the table scrolls instead
                        // of compressing the columns to fit the viewport.
                        .fixedSize(horizontal: true, vertical: false)
                        .markdownTableBorderStyle(.init(color: Color(.separator)))
                        .markdownTableBackgroundStyle(
                            .alternatingRows(
                                Color(.systemBackground),
                                Color(.secondarySystemBackground)
                            )
                        )
                }
                .markdownMargin(top: 0, bottom: 16)
            }
            .tableCell { configuration in
                BoundedTableCellLayout(minWidth: 140, maxWidth: 280) {
                    SelectableProseView(
                        markdown: configuration.content.renderMarkdown(),
                        semibold: configuration.row == 0
                    )
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
            }
    }
}

/// GFM markdown via MarkdownUI, with images (local paths + http) resolved
/// through the host. Used for assistant + user prose.
struct ProseView: View {
    let text: String
    @Environment(\.hostFiles) private var hostFiles

    var body: some View {
        // No `.textSelection(.enabled)`: on iOS it only offers "copy the whole
        // block". Range selection comes from the native text views the
        // `lfgFlat` theme puts inside each paragraph / cell / code block.
        Markdown(text)
            .markdownImageProvider(HostImageProvider(hostFiles: hostFiles))
            .markdownTheme(.lfgFlat)
    }
}

#if DEBUG
/// Launch with `LFG_MARKDOWN_TABLE_FIXTURE=1` to exercise the case where a
/// later cell, rather than the leading cell, determines the row height.
struct MarkdownTableLayoutFixture: View {
    private let markdown = """
    # Table row sizing

    | Property | Validation |
    | --- | --- |
    | font-family | `var(--disp) — Avenir Next / Futura / Century Gothic / Helvetica Neue / Franklin Gothic` |
    | font-weight | 600 |
    | font-size | 16px |
    | letter-spacing | -0.01em |

    The row below the wrapped value must begin after all three lines.
    """

    var body: some View {
        ScrollView {
            ProseView(text: markdown)
                .padding()
        }
        .navigationTitle("Table layout fixture")
        .accessibilityIdentifier("markdownTableLayoutFixture")
    }
}
#endif

private struct HostImageProvider: ImageProvider {
    let hostFiles: HostFiles?
    func makeImage(url: URL?) -> some View {
        Group {
            if let url, let resolved = hostFiles?.resolve(url) ?? (url.scheme != nil ? url : nil) {
                AuthenticatedImage(url: resolved, client: hostFiles?.client)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                EmptyView()
            }
        }
    }
}

private struct AuthenticatedImage: View {
    let url: URL
    let client: LFGClient?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Label("image unavailable", systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            failed = false
            do {
                let data: Data
                if let client { data = try await client.resourceData(from: url) }
                else { data = try await URLSession.shared.data(from: url).0 }
                guard !Task.isCancelled, let decoded = UIImage(data: data) else {
                    if !Task.isCancelled { failed = true }
                    return
                }
                image = decoded
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
        }
    }
}

// MARK: - Inline media attachments (video / pdf / file cards / bare images)

/// Every attachment — image, video, PDF, anything — is a compact tappable card
/// that opens full-screen in `FileViewerSheet`. One rule, no per-type layout:
/// a transcript is a conversation to scan, and inline previews turned an
/// image- or video-heavy session into a wall of media you had to scroll past.
/// The card says what the file is; the tap is how you look at it.
struct MediaAttachmentsView: View {
    let refs: [MediaRef]
    @Environment(\.hostFiles) private var hostFiles
    @State private var viewing: MediaRef?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(refs) { ref in
                fileCard(ref)
            }
        }
        .sheet(item: $viewing) { ref in
            FileViewerSheet(
                ref: ref,
                url: hostFiles?.resolve(rawPath: ref.raw),
                client: hostFiles?.client
            )
        }
    }

    private func fileCard(_ ref: MediaRef) -> some View {
        Button { viewing = ref } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(ref.kind)).font(.title3).foregroundStyle(.secondary)
                Text(ref.filename).font(.subheadline).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func icon(_ kind: MediaKind) -> String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .markdown: return "doc.text"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .other: return "doc"
        }
    }
}

// MARK: - Video

/// Video surface for host files, shown inside `FileViewerSheet`.
///
/// Two reasons this exists instead of SwiftUI's `VideoPlayer`:
/// 1. `VideoPlayer` suppresses `AVPlayerViewController`'s full-screen expand
///    button, so a video could only ever be watched at the size it was given.
///    Hosting the controller directly puts the expand control back.
/// 2. The player is owned by the coordinator, so a body re-evaluation (the
///    transcript re-renders on every SSE delta) no longer builds a fresh
///    `AVPlayer` and restart playback from zero.
///
/// Protected videos are downloaded to a temporary file before this view is
/// created. AVPlayer has no supported arbitrary-header API, so pointing it at a
/// Cloudflare Access URL would silently omit the service credential.
struct HostVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    @MainActor final class Coordinator {
        let controller = AVPlayerViewController()
        var url: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = context.coordinator.controller
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .clear
        // PiP would need the `audio` background mode, which this app doesn't
        // declare — the button would appear and then stall on backgrounding.
        vc.allowsPictureInPicturePlayback = false
        vc.updatesNowPlayingInfoCenter = false
        load(into: context.coordinator)
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        load(into: context.coordinator)
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        vc.player?.pause()
    }

    private func load(into coordinator: Coordinator) {
        guard coordinator.url != url else { return }
        coordinator.url = url
        coordinator.controller.player = AVPlayer(url: url)
    }
}

// MARK: - Full-screen viewer

/// Downloads the file from the host (it lives on the computer, not the phone)
/// with explicit loading/error states — no infinite spinner — then renders it.
struct FileViewerSheet: View {
    let ref: MediaRef
    let url: URL?
    let client: LFGClient?
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case loading, failed(String), data(Data), localVideo(URL) }
    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView(ref.kind == .video ? "Preparing video…" : "Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView("Can't load file", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                case .data(let data):
                    rendered(data)
                case .localVideo(let url):
                    HostVideoPlayer(url: url).ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(ref.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task {
            await load()
        }
        .onDisappear {
            if case .localVideo(let url) = phase { try? FileManager.default.removeItem(at: url) }
        }
    }

    @ViewBuilder private func rendered(_ data: Data) -> some View {
        switch ref.kind {
        case .image:
            if let img = UIImage(data: data) {
                ZoomableImageView(image: img).ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("Not an image", systemImage: "photo")
            }
        case .pdf:
            PDFDataView(data: data)
        case .markdown:
            ScrollView { Markdown(String(decoding: data, as: UTF8.self)).markdownTheme(.lfgFlat).padding() }
        case .other, .video:
            QuickLookView(data: data, filename: ref.filename)
        }
    }

    private func load() async {
        guard let url else { phase = .failed("This file isn't available on the host."); return }
        do {
            if ref.kind == .video {
                let downloaded: URL
                if let client { downloaded = try await client.downloadResource(from: url) }
                else { downloaded = try await URLSession.shared.download(from: url).0 }
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lfg-viewer", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let ext = url.pathExtension.isEmpty ? ref.filename.split(separator: ".").last.map(String.init) ?? "mp4"
                                                    : url.pathExtension
                let local = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                try FileManager.default.moveItem(at: downloaded, to: local)
                phase = .localVideo(local)
            } else {
                let data: Data
                if let client { data = try await client.resourceData(from: url) }
                else { data = try await URLSession.shared.data(from: url).0 }
                phase = .data(data)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct PDFDataView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(data: data)
        return v
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

/// Pinch-to-zoom image viewer backed by `UIScrollView`. Opens fit-to-width,
/// pinches in for detail, and zooms out to fit the whole image. Double-tap
/// toggles between fit-to-width and a 2.5x detail zoom centered on the tap.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomableScrollView {
        let scrollView = ZoomableScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.imageView = imageView
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ uiView: ZoomableScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: ZoomableScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomableScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomableScrollView)?.centerImage()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, let imageView = scrollView.imageView else { return }
            if scrollView.zoomScale > scrollView.fitWidthScale * 1.01 {
                scrollView.setZoomScale(scrollView.fitWidthScale, animated: true)
            } else {
                let target = min(scrollView.maximumZoomScale, scrollView.fitWidthScale * 2.5)
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / target,
                                  height: scrollView.bounds.height / target)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2,
                                           y: point.y - size.height / 2,
                                           width: size.width, height: size.height),
                                animated: true)
            }
        }
    }
}

/// `UIScrollView` subclass laying out a single image: fit-to-width as the
/// initial zoom, fit-whole as the minimum (so tall images can be zoomed out to
/// see entirely), and keeps the image centered while zoomed.
final class ZoomableScrollView: UIScrollView {
    var imageView: UIImageView?
    private(set) var fitWidthScale: CGFloat = 1
    private var hasConfigured = false

    override func layoutSubviews() {
        super.layoutSubviews()
        configureIfNeeded()
        centerImage()
    }

    private func configureIfNeeded() {
        guard !hasConfigured, let imageView, let image = imageView.image,
              bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }
        hasConfigured = true

        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size

        let widthScale = bounds.width / image.size.width
        let heightScale = bounds.height / image.size.height
        let fitWhole = min(widthScale, heightScale)

        fitWidthScale = widthScale
        minimumZoomScale = min(fitWhole, widthScale)   // zoom out to whole image
        maximumZoomScale = max(widthScale, fitWhole) * 4
        zoomScale = widthScale                          // open fit-to-width
    }

    func centerImage() {
        guard let imageView else { return }
        let boundsSize = bounds.size
        var frame = imageView.frame
        frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
        imageView.frame = frame
    }
}

/// QuickLook preview for arbitrary file types, backed by a temp file written
/// from the downloaded bytes.
struct QuickLookView: UIViewControllerRepresentable {
    let data: Data
    let filename: String

    func makeCoordinator() -> Coordinator { Coordinator(data: data, filename: filename) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL
        init(data: Data, filename: String) {
            let safe = filename.replacingOccurrences(of: "/", with: "_")
            let name = safe.isEmpty ? "file" : safe
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: url)
            fileURL = url
        }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}

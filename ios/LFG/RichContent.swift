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
struct HostFiles: Sendable, Equatable {
    let baseURL: URL
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

extension MarkdownUI.Theme {
    /// GitHub styling, but with the body-text background container removed so the
    /// assistant response flows directly on the page (no gray box). Code blocks,
    /// inline code, headings, lists, tables keep their own styling.
    static var lfgFlat: MarkdownUI.Theme {
        MarkdownUI.Theme.gitHub
            .text {
                ForegroundColor(.primary)
                BackgroundColor(.clear)
                FontSize(16)
            }
    }
}

/// GFM markdown via MarkdownUI, with images (local paths + http) resolved
/// through the host. Used for assistant + user prose.
struct ProseView: View {
    let text: String
    @Environment(\.hostFiles) private var hostFiles

    var body: some View {
        Markdown(text)
            .markdownImageProvider(HostImageProvider(hostFiles: hostFiles))
            .markdownTheme(.lfgFlat)
            // Tables size columns to their content and scroll horizontally so
            // wide tables stay readable instead of being crushed to fit.
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .textSelection(.enabled)
    }
}

private struct HostImageProvider: ImageProvider {
    let hostFiles: HostFiles?
    func makeImage(url: URL?) -> some View {
        Group {
            if let url, let resolved = hostFiles?.resolve(url) ?? (url.scheme != nil ? url : nil) {
                AsyncImage(url: resolved) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: Label("image unavailable", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                    default: ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                EmptyView()
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
            FileViewerSheet(ref: ref, url: hostFiles?.resolve(rawPath: ref.raw))
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
/// It streams from the host rather than downloading first — a two-minute clip
/// is tens of megabytes, and `FileViewerSheet`'s download path would hold all
/// of it in memory before the first frame.
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
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case loading, failed(String), data(Data) }
    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            Group {
                if ref.kind == .video, let url {
                    HostVideoPlayer(url: url)                    // stream remote video
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    switch phase {
                    case .loading:
                        ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failed(let message):
                        ContentUnavailableView("Can't load file", systemImage: "exclamationmark.triangle",
                                               description: Text(message))
                    case .data(let data):
                        rendered(data)
                    }
                }
            }
            .navigationTitle(ref.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task {
            guard ref.kind != .video else { return }
            await load()
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
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                phase = .failed("Host returned \(http.statusCode). The file may have moved or sit outside the served folders.")
                return
            }
            phase = .data(data)
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

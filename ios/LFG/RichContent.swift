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

    /// Rendition widths the app asks the server for (`w=`; see
    /// `file-thumbs.ts`). Inline transcript images are read at phone width;
    /// the full-screen viewer gets enough pixels for a 3× screen at 2× pinch.
    /// Both are 5–40× fewer bytes than the PNG the agent wrote.
    static let inlineImageWidth = 1200
    static let viewerImageWidth = 2400

    func fileURL(forPath path: String, maxWidth: Int? = nil) -> URL? {
        client.hostFileURL(forPath: path, maxWidth: maxWidth)
    }

    /// Turn a relative path into an absolute host path by joining the session cwd.
    /// A `~`-rooted path is passed through untouched: only the host knows its own
    /// home directory, and `/api/file` expands it. Joining it to the cwd instead
    /// (which is what "not absolute" used to mean here) produced a path that
    /// could never exist, so every `~/…` file an agent handed over 404'd.
    private func absolutePath(_ path: String) -> String? {
        if path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") { return path }
        guard let cwd, !cwd.isEmpty else { return nil }
        return (cwd.hasSuffix("/") ? cwd : cwd + "/") + path
    }

    /// Resolve a URL parsed out of markdown/text to something loadable.
    /// `maxWidth` only affects host files (a rendition request); external URLs
    /// pass through untouched.
    func resolve(_ url: URL, maxWidth: Int? = nil) -> URL? {
        if let s = url.scheme?.lowercased(), s == "http" || s == "https" { return url }
        let path = url.scheme == "file" ? url.path : url.absoluteString
        guard let abs = absolutePath(path) else { return nil }
        return fileURL(forPath: abs, maxWidth: maxWidth)
    }

    func resolve(rawPath: String, maxWidth: Int? = nil) -> URL? {
        if rawPath.hasPrefix("http://") || rawPath.hasPrefix("https://") { return URL(string: rawPath) }
        guard let abs = absolutePath(rawPath) else { return nil }
        return fileURL(forPath: abs, maxWidth: maxWidth)
    }

    /// The URL `FileViewerSheet` opens for an attachment. The ONE place that
    /// decides an image opens as a 2400 px rendition (the viewer is for
    /// reading a screenshot, not archiving the PNG) — every card that opens
    /// the viewer goes through here, so no call site can forget the width.
    func viewerURL(for ref: MediaRef) -> URL? {
        resolve(rawPath: ref.raw, maxWidth: ref.kind == .image ? Self.viewerImageWidth : nil)
    }
}

/// Decoded inline images, keyed by URL, so a transcript row that leaves and
/// re-enters the lazy stack doesn't decode (or, past `URLCache`, re-fetch)
/// the same screenshot. Cost is the bitmap size; the limit is generous
/// because a 1200 px rendition is ~4 MB decoded.
@MainActor
enum InlineImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 96 << 20
        return c
    }()

    static func image(for url: URL) -> UIImage? { cache.object(forKey: url.absoluteString as NSString) }

    static func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
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
            if let url,
               let resolved = hostFiles?.resolve(url, maxWidth: HostFiles.inlineImageWidth)
                   ?? (url.scheme != nil ? url : nil) {
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
            if let cached = InlineImageCache.image(for: url) { image = cached; return }
            do {
                let data: Data
                if let client { data = try await client.resourceData(from: url) }
                else { data = try await URLSession.shared.data(from: url).0 }
                guard !Task.isCancelled, let decoded = UIImage(data: data) else {
                    if !Task.isCancelled { failed = true }
                    return
                }
                InlineImageCache.store(decoded, for: url)
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
                files: [ref],
                hostFiles: hostFiles
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
/// The video is STREAMED, never downloaded first. AVPlayer fetches byte ranges
/// and starts once it has the header and a few seconds of frames — on the
/// 200–400 MB sim recordings agents produce, the old download-then-play path
/// meant minutes of "Preparing video…" (see the 2026-09-17 media diagnosis).
///
/// AVPlayer has no supported way to add request headers, and Cloudflare Access
/// refuses a request without the service-token headers (the `CF_Authorization`
/// cookie alone is a 403). So for a credentialed host the asset goes through
/// `StreamingResourceLoader`, which answers AVPlayer's range requests via
/// `LFGClient.resourceRequest(for:)`; an uncredentialed host (LAN, loopback)
/// gets the plain URL — `/api/file` already answers `206`.
struct HostVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let client: LFGClient?

    @MainActor final class Coordinator {
        let controller = AVPlayerViewController()
        var url: URL?
        /// Retained here: `AVAssetResourceLoader` holds its delegate weakly.
        var loader: StreamingResourceLoader?
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
        coordinator.loader?.invalidate()
    }

    private func load(into coordinator: Coordinator) {
        guard coordinator.url != url else { return }
        coordinator.url = url
        coordinator.loader?.invalidate()
        coordinator.loader = nil
        let asset: AVURLAsset
        if let client, client.authenticatesRequests(to: url) {
            let loader = StreamingResourceLoader(origin: url, client: client)
            coordinator.loader = loader
            asset = loader.makeAsset()
        } else {
            asset = AVURLAsset(url: url)
        }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        coordinator.controller.player = player
        player.play()
    }
}

/// Answers `AVAssetResourceLoader`'s byte-range requests for one host video by
/// forwarding each one through the authenticated transport.
///
/// AVPlayer opens the asset with a custom scheme (`lfg-stream://…`) so the
/// loader is consulted instead of the network. Each loading request becomes
/// one `URLSessionDataTask` carrying `Range:` plus the Access headers; the
/// response's `Content-Range` fills in the content information (type, total
/// length, ranges supported) and every received chunk is handed to the
/// request as it arrives, so playback starts before the request finishes.
/// Cancelled loading requests (seeks, dismissal) cancel their task.
final class StreamingResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let scheme = "lfg-stream"

    private let origin: URL
    private let client: LFGClient
    private let lock = NSLock()
    private var requestsByTask: [Int: AVAssetResourceLoadingRequest] = [:]
    private var tasksByRequest: [ObjectIdentifier: URLSessionDataTask] = [:]
    private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "lfg.streaming-resource-loader"
        return q
    }()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        // Media bytes must not enter URLCache: a 235 MB range set would evict
        // every screenshot rendition the transcript relies on.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Idle timeout, not total: a slow path (50 KB/s) is fine as long as
        // bytes keep flowing.
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    init(origin: URL, client: LFGClient) {
        self.origin = origin
        self.client = client
    }

    /// The asset AVPlayer should play. Query string (the `path=`) is preserved
    /// but irrelevant — every request maps back to `origin`.
    func makeAsset() -> AVURLAsset {
        var comps = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        comps?.scheme = Self.scheme
        let asset = AVURLAsset(url: comps?.url ?? origin)
        asset.resourceLoader.setDelegate(self, queue: DispatchQueue(label: "lfg.streaming-resource-loader.avf"))
        return asset
    }

    func invalidate() {
        lock.lock()
        let tasks = Array(tasksByRequest.values)
        tasksByRequest.removeAll()
        requestsByTask.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
        session.invalidateAndCancel()
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let dataRequest = loadingRequest.dataRequest else { return false }
        var request = client.resourceRequest(for: origin)
        request.setValue(
            StreamingRange.header(offset: dataRequest.requestedOffset,
                                  length: dataRequest.requestedLength,
                                  toEnd: dataRequest.requestsAllDataToEndOfResource),
            forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request)
        lock.lock()
        requestsByTask[task.taskIdentifier] = loadingRequest
        tasksByRequest[ObjectIdentifier(loadingRequest)] = task
        lock.unlock()
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        lock.lock()
        let task = tasksByRequest.removeValue(forKey: ObjectIdentifier(loadingRequest))
        if let task { requestsByTask.removeValue(forKey: task.taskIdentifier) }
        lock.unlock()
        task?.cancel()
    }

    // MARK: URLSessionDataDelegate

    private func loadingRequest(for task: URLSessionTask) -> AVAssetResourceLoadingRequest? {
        lock.lock(); defer { lock.unlock() }
        return requestsByTask[task.taskIdentifier]
    }

    private func forget(_ task: URLSessionTask) -> AVAssetResourceLoadingRequest? {
        lock.lock(); defer { lock.unlock() }
        guard let request = requestsByTask.removeValue(forKey: task.taskIdentifier) else { return nil }
        tasksByRequest.removeValue(forKey: ObjectIdentifier(request))
        return request
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let loadingRequest = loadingRequest(for: dataTask) else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            _ = forget(dataTask)
            loadingRequest.finishLoading(with: URLError(status == 403 ? .userAuthenticationRequired : .badServerResponse))
            completionHandler(.cancel)
            return
        }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = StreamingRange.uniformType(mimeType: http.mimeType,
                                                          pathExtension: origin.pathExtension)
            let contentLength = http.expectedContentLength >= 0 ? http.expectedContentLength : nil
            if let total = StreamingRange.totalLength(
                contentRange: http.value(forHTTPHeaderField: "Content-Range"),
                contentLength: contentLength) {
                info.contentLength = total
            }
            info.isByteRangeAccessSupported = http.statusCode == 206
                || http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        loadingRequest(for: dataTask)?.dataRequest?.respond(with: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let loadingRequest = forget(task) else { return }
        if let error, (error as? URLError)?.code != .cancelled {
            loadingRequest.finishLoading(with: error)
        } else if !loadingRequest.isCancelled {
            loadingRequest.finishLoading()
        }
    }
}

// MARK: - Full-screen viewer

/// Downloads the file from the host (it lives on the computer, not the phone)
/// with explicit loading/error states — no infinite spinner — then renders it.
struct FileViewerSheet: View {
    private let sequence: FilePreviewSequence
    private let hostFiles: HostFiles?
    @State private var selectedID: String
    @State private var imageIsZoomed = false
    @State private var pagingForward = true

    @Environment(\.dismiss) private var dismiss

    init(ref: MediaRef, files: [MediaRef], hostFiles: HostFiles?) {
        let sequence = FilePreviewSequence(files: files, selected: ref)
        self.sequence = sequence
        self.hostFiles = hostFiles
        _selectedID = State(initialValue: sequence.initialID ?? ref.id)
    }

    private var selectedRef: MediaRef? {
        sequence.files.first(where: { $0.id == selectedID })
    }

    private var selectedIndex: Int? {
        sequence.files.firstIndex(where: { $0.id == selectedID })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let ref = selectedRef {
                    FileViewerPage(
                        ref: ref,
                        url: hostFiles?.viewerURL(for: ref),
                        client: hostFiles?.client,
                        onImageZoomChanged: { imageIsZoomed = $0 }
                    )
                    .id(ref.id)
                    .accessibilityIdentifier("filePreviewPage_\(ref.id)")
                    .transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(pagingGesture)
            .accessibilityIdentifier("filePreviewPager")
            .navigationTitle(selectedRef?.filename ?? "File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("filePreviewDoneButton")
                }
            }
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: pagingForward ? .trailing : .leading),
            removal: .move(edge: pagingForward ? .leading : .trailing)
        )
    }

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard !imageIsZoomed else { return }
                let translation = value.translation
                guard abs(translation.width) > abs(translation.height),
                      abs(translation.width) >= 60 else { return }
                moveSelection(by: translation.width < 0 ? 1 : -1)
            }
    }

    private func moveSelection(by offset: Int) {
        guard let selectedIndex else { return }
        let destination = selectedIndex + offset
        guard sequence.files.indices.contains(destination) else { return }
        pagingForward = offset > 0
        imageIsZoomed = false
        withAnimation(.snappy(duration: 0.28)) {
            selectedID = sequence.files[destination].id
        }
    }
}

/// One page in the file preview. The pager only constructs its current page,
/// so hidden videos cannot start playing beside the one the user is watching.
private struct FileViewerPage: View {
    let ref: MediaRef
    let url: URL?
    let client: LFGClient?
    let onImageZoomChanged: (Bool) -> Void

    enum Phase: Equatable { case loading, failed(String), data(Data), video(URL) }
    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("Can't load file", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .data(let data):
                rendered(data)
            case .video(let url):
                // Streams from the host; the player shows its own buffering
                // state, so there is no app-level "Preparing…" phase.
                HostVideoPlayer(url: url, client: client).ignoresSafeArea(edges: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await load()
        }
        .onDisappear { onImageZoomChanged(false) }
    }

    @ViewBuilder private func rendered(_ data: Data) -> some View {
        switch ref.kind {
        case .image:
            if let img = UIImage(data: data) {
                ZoomableImageView(image: img, onZoomChanged: onImageZoomChanged)
                    .ignoresSafeArea(edges: .bottom)
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
        if ref.kind == .video {
            phase = .video(url)
            return
        }
        do {
            let data: Data
            if let client { data = try await client.resourceData(from: url) }
            else { data = try await URLSession.shared.data(from: url).0 }
            guard !Task.isCancelled else { return }
            phase = .data(data)
        } catch is CancellationError {
            return
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
    var onZoomChanged: (Bool) -> Void = { _ in }

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

    func makeCoordinator() -> Coordinator { Coordinator(onZoomChanged: onZoomChanged) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: ZoomableScrollView?
        private let onZoomChanged: (Bool) -> Void
        private var reportedZoomed = false

        init(onZoomChanged: @escaping (Bool) -> Void) {
            self.onZoomChanged = onZoomChanged
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomableScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let scrollView = scrollView as? ZoomableScrollView else { return }
            scrollView.centerImage()
            let zoomed = scrollView.zoomScale > scrollView.fitWidthScale * 1.01
            guard zoomed != reportedZoomed else { return }
            reportedZoomed = zoomed
            DispatchQueue.main.async { [onZoomChanged] in onZoomChanged(zoomed) }
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

    /// At fit width (or farther out), a horizontal drag means “next/previous
    /// file”, not “pan an image that has no horizontal overflow”. Returning
    /// false lets the containing page view own that gesture. Once zoomed in,
    /// the image keeps the drag so the user can inspect details normally.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer,
           zoomScale <= fitWidthScale * 1.01 {
            let velocity = panGestureRecognizer.velocity(in: self)
            if abs(velocity.x) > abs(velocity.y) {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
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

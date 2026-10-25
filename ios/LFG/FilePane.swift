import SwiftUI
import WebKit
import UniformTypeIdentifiers
import LFGCore

struct FilePaneNavigation: Sendable {
    var windowSize = CGSize.zero
    var needsInputCount = 0
    var update: @MainActor @Sendable (Bool, Bool) -> Void = { _, _ in }
    var showList: @MainActor @Sendable () -> Void = {}
}
private struct FilePaneNavigationKey: EnvironmentKey {
    static let defaultValue = FilePaneNavigation()
}
private struct OpenFilePaneKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    var filePaneNavigation: FilePaneNavigation {
        get { self[FilePaneNavigationKey.self] }
        set { self[FilePaneNavigationKey.self] = newValue }
    }
    var openFilePaneID: String? {
        get { self[OpenFilePaneKey.self] }
        set { self[OpenFilePaneKey.self] = newValue }
    }
}

/// Remember readers across navigation without retaining player or web view instances.
@MainActor enum FilePaneMemory {
    static func load(_ key: String) -> FilePaneState {
        guard let data = UserDefaults.standard.data(forKey: "lfg.filePane.\(key)"),
              let state = try? JSONDecoder().decode(FilePaneState.self, from: data) else { return FilePaneState() }
        return state
    }
    static func save(_ state: FilePaneState, key: String) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "lfg.filePane.\(key)")
        }
    }
}

/// Three columns use the compact wide reader while preserving a usable transcript.
enum FilePaneSizing {
    static func width(preferred: CGFloat, available: CGFloat) -> CGFloat {
        max(0, min(preferred, max(280, available - 410), available < 1100 ? 600 : .infinity))
    }
}

/// The transcript retains one structural identity while the preview changes size or axis.
struct FilePaneContainer<Content: View, Header: View>: View {
    @Binding var state: FilePaneState
    let resources: TranscriptResources
    let messages: [SessionMessage]
    let revision: String
    let sessionTitle: String
    let sessionIsBusy: Bool
    let hostFiles: HostFiles?
    let keyboardVisible: Bool
    let onReveal: (String) -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @Environment(\.filePaneNavigation) private var navigation
    @State private var localSize = CGSize.zero
    @State private var drag: CGFloat = 0
    @State private var sheetPresented = false

    private var windowSize: CGSize {
        navigation.windowSize == .zero ? localSize : navigation.windowSize
    }
    private var presentation: FilePaneLayout.Presentation {
        FilePaneLayout.presentation(width: windowSize.width, height: windowSize.height,
            isPad: UIDevice.current.userInterfaceIdiom == .pad, portraitDocked: state.portraitDocked)
    }
    private var inline: Bool { state.isOpen && presentation != .sheet }

    var body: some View {
        GeometryReader { geometry in
            let side = presentation == .side
            let full = inline && state.fullWidth
            let baseWidth = FilePaneSizing.width(preferred: CGFloat(state.width), available: geometry.size.width)
            let width = FilePaneSizing.width(preferred: baseWidth - drag, available: geometry.size.width)
            let fraction = keyboardVisible ? 0.4 : state.portraitFraction
            let paneHeight = min(geometry.size.height, max(180, geometry.size.height * fraction + drag))
            // A single layout avoids unmounting the transcript when opening a file.
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if inline { header().padding(.trailing, side ? 6 : 0).frame(height: 52).offset(y: side ? -4 : -2).zIndex(1) }
                    content().padding(.horizontal, inline && side ? 5 : 0)
                }
                .frame(width: full ? geometry.size.width : (inline && side ? max(0, geometry.size.width - width - 10) : geometry.size.width),
                       height: inline && !side && !full ? max(0, geometry.size.height - paneHeight - 20) : geometry.size.height)
                .clipShape(FilePaneTranscriptClip(enabled: inline))
                .offset(y: inline && !side && !full ? paneHeight + 20 : 0)
                .opacity(full ? 0 : 1)
                .allowsHitTesting(!full)
                .accessibilityHidden(full)

                if inline {
                    reader(canDock: false)
                        .frame(width: full ? geometry.size.width : (side ? width : geometry.size.width),
                               height: full || side ? geometry.size.height : paneHeight)
                        .offset(x: !full && side ? geometry.size.width - width : 0)
                    if !full {
                        resizeHandle(side: side, available: geometry.size)
                            .frame(width: side ? 16 : geometry.size.width, height: side ? geometry.size.height : 20)
                            .offset(x: side ? geometry.size.width - width - 16 : 0, y: side ? 0 : paneHeight)
                    }
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { localSize = $0 }
        }
        .padding(.top, inline ? 10 : 0)
        .padding(.leading, inline && (state.fullWidth || presentation == .top) ? 10 : 0)
        .padding(.trailing, inline ? 10 : 0)
        .padding(.bottom, inline ? -10 : 0)
        .environment(\.openFilePaneID, state.isOpen && !state.showingFiles ? state.selection?.id : nil)
        .toolbar(inline ? .hidden : .automatic, for: .navigationBar)
        .onChange(of: state.isOpen, initial: true) { _, _ in synchronize() }
        .onChange(of: presentation) { _, _ in synchronize() }
        .onChange(of: state.fullWidth) { _, _ in synchronize() }
        .onChange(of: windowSize) { _, _ in synchronize() }
        .sheet(isPresented: $sheetPresented, onDismiss: {
            if presentation == .sheet { state.close() }
        }) {
            reader(canDock: UIDevice.current.userInterfaceIdiom == .pad && windowSize.width >= 600)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(S2.surface)
        }
        .onDisappear { navigation.update(false, false) }
        .background {
            Button("Close file pane") { state.close() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!state.isOpen)
                .hidden().accessibilityHidden(true)
        }
    }

    private func synchronize() {
        sheetPresented = state.isOpen && presentation == .sheet
        navigation.update(inline, state.fullWidth)
    }

    private func reader(canDock: Bool) -> some View {
        FilePaneReader(state: $state, resources: resources, messages: messages, hostFiles: hostFiles,
                       revision: revision, sessionTitle: sessionTitle, sessionIsBusy: sessionIsBusy,
                       canDock: canDock, isSheet: presentation == .sheet, isPortrait: windowSize.height > windowSize.width, onReveal: onReveal)
            .id(state.showingFiles ? "index" : state.selection?.id ?? "none")
    }

    private func resizeHandle(side: Bool, available: CGSize) -> some View {
        Button {
            if side { state.setWidth(state.width == 720 ? 420 : 720) }
            else { state.portraitFraction = state.portraitFraction < 0.5 ? 0.55 : (state.portraitFraction < 0.65 ? 0.7 : 0.4) }
        } label: {
            Capsule().fill(Color(.systemGray2)).frame(width: side ? 5 : 44, height: side ? 44 : 5)
                .offset(x: side ? 3 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resize file pane")
        .accessibilityIdentifier("filePaneResizeHandle")
        .accessibilityValue(side ? "\(Int(FilePaneSizing.width(preferred: state.width, available: available.width))) points" : "\(Int((keyboardVisible ? 0.4 : state.portraitFraction) * 100)) percent")
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .onChanged { drag = side ? $0.translation.width : $0.translation.height }
            .onEnded { value in
                drag = 0
                if side {
                    switch FilePaneLayout.horizontalSnap(proposed: FilePaneSizing.width(preferred: state.width, available: available.width) - value.translation.width) {
                    case .close: state.close()
                    case .full: state.fullWidth = true
                    case .width(let width): state.setWidth(width)
                    }
                } else {
                    switch FilePaneLayout.portraitSnap(fraction: state.portraitFraction + value.translation.height / available.height) {
                    case .close: state.close()
                    case .sheet: state.portraitDocked = false; state.fullWidth = false
                    case .fraction(let fraction): state.portraitFraction = fraction
                    }
                }
            })
    }
}

private struct FilePaneTranscriptClip: Shape {
    let enabled: Bool
    func path(in rect: CGRect) -> Path {
        Path(enabled ? rect : rect.insetBy(dx: -10_000, dy: -10_000))
    }
}

struct FilePaneReader: View {
    @Binding var state: FilePaneState
    let resources: TranscriptResources
    let messages: [SessionMessage]
    let hostFiles: HostFiles?
    let revision: String
    let sessionTitle: String
    let sessionIsBusy: Bool
    let canDock: Bool
    let isSheet: Bool
    let isPortrait: Bool
    let onReveal: (String) -> Void
    @Environment(\.openURL) private var openURL
    @State private var showingLinks = false
    @State private var updated = false
    @State private var webError: String?
    @State private var webRetry = 0
    @State private var currentWebURL: URL?

    private var ref: MediaRef? { state.showingFiles ? nil : state.selection }
    private var sourceID: String? {
        guard let ref else { return nil }
        return resources.files.first(where: { $0.id == ref.id })?.messageID ??
            resources.links.first(where: { $0.id == ref.id })?.messageID
    }
    private var media: [MediaRef] { resources.files.map(\.ref).filter { $0.kind == .image || $0.kind == .video } }
    private var webURL: URL? {
        guard let ref, let url = hostFiles?.resolve(rawPath: ref.raw) ?? URL(string: ref.raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let ext = (URL(string: ref.raw)?.pathExtension ?? (ref.raw as NSString).pathExtension).lowercased()
        if ["html", "htm"].contains(ext), !ref.raw.hasPrefix("http"), hostFiles != nil {
            var components = URLComponents()
            components.scheme = "lfg-file"
            components.host = "preview"
            let path = ref.raw.hasPrefix("/") ? ref.raw : "\(hostFiles?.cwd ?? "")/\(ref.raw)"
            components.path = path
            return components.url
        }
        return ["html", "htm"].contains(ext) || (ref.kind == .other && (ref.raw.hasPrefix("http://") || ref.raw.hasPrefix("https://"))) ? url : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 64).padding(.leading, state.showingFiles ? 18 : 10).padding(.trailing, 10)
            Group {
                if state.showingFiles { index }
                else if let ref {
                    if let webURL {
                        PaneWebView(url: webURL, hostFiles: hostFiles, revision: revision, reloadID: webRetry,
                            onError: { webError = $0 }, onLocation: { currentWebURL = $0 })
                            .overlay {
                                if let webError {
                                    VStack(spacing: 16) {
                                        ContentUnavailableView("Can't load page", systemImage: "wifi.exclamationmark", description: Text(webError))
                                        Button("Try again") { self.webError = nil; webRetry += 1 }
                                            .accessibilityIdentifier("filePaneWebRetry")
                                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(S2.surface)
                                }
                            }
                    } else {
                        FileViewerPage(ref: ref, url: versioned(hostFiles?.viewerURL(for: ref) ?? URL(string: ref.raw)),
                            originalURL: versioned(hostFiles?.shareURL(for: ref) ?? URL(string: ref.raw)),
                            client: hostFiles?.client, onImageZoomChanged: { _ in }, allowsPictureInPicture: true)
                            .id(ref.id)
                            .padding(.bottom, ref.kind == .image || ref.kind == .video ? 84 : 0)
                    }
                } else { ContentUnavailableView("Choose a file", systemImage: "doc") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(state.showingFiles ? S2.surface : (ref?.kind == .image || ref?.kind == .video ? Color.black : Color(.systemBackground)), in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, state.showingFiles ? 0 : 8)
            .padding(.bottom, state.showingFiles ? 0 : 8)

        }
        .overlay(alignment: .bottom) {
            if let ref, ref.kind == .image || ref.kind == .video { mediaStrip.padding(.bottom, 22) }
        }
        .background(S2.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(S2.surfaceBorder, lineWidth: 0.5) }
        .accessibilityElement(children: .contain).accessibilityLabel("File preview")
        .accessibilityIdentifier("filePaneReader")
        .onChange(of: state.selection?.id) { _, _ in updated = false; webError = nil }
        .onChange(of: revision) { old, new in
            if !old.isEmpty, !new.isEmpty { updated = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if state.fullWidth && !isSheet {
                Button { state.fullWidth = false } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                        Circle().fill(sessionIsBusy ? .green : .gray).frame(width: 8, height: 8)
                        Text(sessionTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }.padding(.horizontal, 12).frame(height: 44).frame(maxWidth: 240)
                        .background(S2.chip, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("Return to transcript, \(sessionTitle)")
                    .accessibilityIdentifier("filePaneReturnToTranscript")
            } else if !state.showingFiles {
                circle("All files and links", icon: "chevron.left", id: "filePaneAllFiles") { state.showFiles() }
            }
            if webURL != nil {
                HStack(spacing: 8) {
                    Image(systemName: (currentWebURL ?? webURL)?.scheme == "lfg-file" ? "doc.text" : "link").font(.system(size: 14)).foregroundStyle(S2.secondaryInk)
                    (Text(headerTitle).foregroundColor(.primary) + Text(addressFolder).foregroundColor(S2.secondaryInk))
                        .font(.system(size: 15)).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { webError = nil; webRetry += 1 } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 32, height: 32)
                    }.buttonStyle(.plain).accessibilityLabel("Reload page").accessibilityIdentifier("filePaneReload")
                }.padding(.leading, 14).padding(.trailing, 6).frame(height: 40)
                    .background(S2.chip, in: Capsule())
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(headerTitle).font(.system(size: 17, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(metadata).font(.system(size: 13)).foregroundStyle(S2.secondaryInk).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 0) {
                if canDock {
                    Button { state.portraitDocked = true; state.fullWidth = false } label: {
                        actionLabel("rectangle.topthird.inset.filled")
                    }.accessibilityLabel("Dock above transcript").accessibilityIdentifier("filePaneDock")
                } else if !isSheet {
                    Button {
                        if isPortrait { state.portraitDocked = false; state.fullWidth = false }
                        else { state.fullWidth.toggle() }
                    } label: {
                        actionLabel(isPortrait ? "rectangle.bottomthird.inset.filled" : state.fullWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }.accessibilityLabel(isPortrait ? "Show file as sheet" : state.fullWidth ? "Return to split view" : "Use the full width")
                        .accessibilityIdentifier("filePaneExpand")
                }
                if let ref {
                    Menu {
                        Button("Show in transcript", systemImage: "text.bubble") {
                            if let sourceID { onReveal(sourceID) }
                        }.disabled(sourceID == nil).accessibilityIdentifier("filePaneReveal")
                        Button("Copy path", systemImage: "doc.on.doc") { UIPasteboard.general.string = ref.raw }
                            .accessibilityIdentifier("filePaneCopyPath")
                        if let url = currentWebURL ?? webURL, ["http", "https"].contains(url.scheme ?? "") {
                            Button("Open in Safari", systemImage: "safari") { UIApplication.shared.open(url) }
                                .accessibilityIdentifier("filePaneOpenSafari")
                        }
                    } label: { actionLabel("ellipsis") }
                    .accessibilityLabel("More file actions").accessibilityIdentifier("filePaneMenu")
                } else {
                    Menu {
                        Button("Copy all paths", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = (resources.files.map { $0.ref.raw } + resources.links.map { $0.link.url }).joined(separator: "\n")
                        }.accessibilityIdentifier("filePaneCopyAllPaths")
                    } label: { actionLabel("ellipsis") }
                    .accessibilityLabel("More file actions").accessibilityIdentifier("filePaneMenu")
                }
            }.buttonStyle(.plain).foregroundStyle(.primary).background(S2.chip, in: Capsule())
            circle("Close file pane", icon: "xmark", id: "filePaneClose") { state.close() }
        }
    }

    private var addressFolder: String {
        guard (currentWebURL ?? webURL)?.scheme == "lfg-file", let ref else { return "" }
        return " · \(((ref.raw as NSString).deletingLastPathComponent as NSString).lastPathComponent)"
    }

    private var headerTitle: String {
        if let url = currentWebURL ?? webURL, url.scheme != "lfg-file" { return url.absoluteString }
        return ref?.filename ?? "Files & links"
    }

    private var metadata: String {
        guard let ref else { return "Shared in this session" }
        if let url = currentWebURL ?? webURL, url.scheme != "lfg-file" { return url.host ?? url.absoluteString }
        let folder = (ref.raw as NSString).deletingLastPathComponent
        let attachment = resources.files.first { $0.id == ref.id }
        let age = attachment?.ts.map { max(0, (Date().timeIntervalSince1970 * 1000 - $0) / 60_000) }
        return "\((folder as NSString).lastPathComponent) · \(updated ? "updated just now" : age.map { $0 < 1 ? "just now" : "\(Int($0))m ago" } ?? "Shared file")"
    }

    private func versioned(_ url: URL?) -> URL? {
        guard let ref, !ref.raw.hasPrefix("http://"), !ref.raw.hasPrefix("https://"),
              let url, !revision.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "lfgRevision", value: revision)]
        return components.url
    }

    private func actionLabel(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 15, weight: .medium))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    private func circleLabel(_ icon: String) -> some View {
        actionLabel(icon).background(S2.chip, in: Circle())
    }
    private func circle(_ label: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(icon) }.buttonStyle(.plain)
            .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private var index: some View {
        VStack(spacing: 14) {
            Picker("Resources", selection: $showingLinks) {
                Text("Files \(resources.files.count)").tag(false)
                Text("Links \(resources.links.count)").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("filePaneIndexTabs")
            ScrollView {
                LazyVStack(spacing: 0) {
                    if showingLinks {
                        ForEach(resources.links) { item in
                            resourceRow(MediaRef(raw: item.link.url, kind: .other, label: item.link.label), meta: URL(string: item.link.url)?.host ?? item.link.url)
                        }
                    } else {
                        ForEach([MediaKind.image, .video, .other], id: \.self) { kind in
                            let files = resources.files.filter { kind == .other ? ![.image, .video].contains($0.ref.kind) : $0.ref.kind == kind }
                            if !files.isEmpty {
                                HStack(spacing: 6) {
                                    Text(sectionName(kind)).fontWeight(.semibold)
                                    Text("\(files.count)").foregroundStyle(S2.metaInk)
                                }.font(.system(size: 13)).foregroundStyle(S2.secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 10).padding(.bottom, 4)
                                ForEach(files) { item in resourceRow(item.ref, meta: item.ref.raw) }
                            }
                        }
                    }
                    if showingLinks ? resources.links.isEmpty : resources.files.isEmpty {
                        ContentUnavailableView("Nothing shared yet", systemImage: "doc")
                    }
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16).accessibilityElement(children: .contain)
            .accessibilityIdentifier("filePaneIndex")
    }
    private func sectionName(_ kind: MediaKind) -> String {
        switch kind { case .image: "Images"; case .video: "Videos"; default: "Documents" }
    }
    private func resourceRow(_ item: MediaRef, meta: String) -> some View {
        Button { state.open(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.kind == .image ? "photo" : item.kind == .video ? "video" : "doc").frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.filename).font(.body).lineLimit(1)
                    Text(meta).font(.system(size: 13)).foregroundStyle(S2.secondaryInk).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if state.newFiles.contains(item.id) { Text("New").font(.caption).foregroundStyle(.blue) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(S2.metaInk)
            }.padding(.vertical, 10).padding(.leading, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("filePaneRow_\(item.filename)")
            .overlay(alignment: .bottom) { Divider() }
    }
    private var mediaStrip: some View {
        ScrollView(.horizontal) { mediaTiles.padding(.horizontal, 8) }
            .scrollIndicators(.hidden)
            .frame(width: min(CGFloat(media.count * 38 + 8), max(100, state.width - 32)), height: 60)
            .background(S2.surface, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain).accessibilityLabel("Images and videos")
            .accessibilityIdentifier("filePaneMediaStrip")
    }

    private var mediaTiles: some View {
        HStack(spacing: 8) {
            ForEach(media) { item in
                Button { state.open(item) } label: {
                    Image(systemName: item.kind == .image ? "photo" : "video")
                        .font(.system(size: 14)).foregroundStyle(S2.secondaryInk)
                        .frame(width: 30, height: 46).background(S2.chip, in: RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(item.id == ref?.id ? Color.blue : .clear, lineWidth: 2) }
                }.buttonStyle(.plain).accessibilityLabel("Open \(item.filename)")
                    .accessibilityIdentifier("filePaneMedia_\(item.filename)")
            }
        }
    }
}

/// WKWebView keeps its default persistent store, independent of Safari sign-ins.
struct PaneWebView: UIViewRepresentable {
    let url: URL
    let hostFiles: HostFiles?
    let revision: String
    let reloadID: Int
    let onError: (String?) -> Void
    let onLocation: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let hostFiles {
            configuration.setURLSchemeHandler(HostFileWebScheme(hostFiles: hostFiles), forURLScheme: "lfg-file")
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.accessibilityIdentifier = "filePaneWebView"
        view.allowsBackForwardNavigationGestures = true
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        let identity = "\(url.absoluteString)|\(revision)"
        context.coordinator.onError = onError
        context.coordinator.onLocation = onLocation
        if context.coordinator.identity == identity {
            if context.coordinator.reloadID != reloadID {
                context.coordinator.reloadID = reloadID
                view.reloadFromOrigin()
            }
            return
        }
        context.coordinator.identity = identity
        context.coordinator.reloadID = reloadID
        var request = hostFiles?.client.resourceRequest(for: url) ?? URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        view.load(request)
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var identity: String?
        var reloadID = 0
        var onError: ((String?) -> Void)?
        var onLocation: ((URL) -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onError?(nil)
            if let url = webView.url { onLocation?(url) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError?(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError?(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(navigationAction.request)
            return nil
        }
    }
}

/// Resolve relative HTML assets through the same authenticated host-file API.
@MainActor final class HostFileWebScheme: NSObject, WKURLSchemeHandler {
    let hostFiles: HostFiles
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(hostFiles: HostFiles) { self.hostFiles = hostFiles }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        guard let requested = urlSchemeTask.request.url,
              let resource = hostFiles.resolve(rawPath: requested.path) else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        tasks[id] = Task { @MainActor in
            do {
                var components = URLComponents(url: resource, resolvingAgainstBaseURL: false)!
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "lfgPreviewFetch", value: UUID().uuidString)]
                let data = try await hostFiles.client.resourceData(from: components.url ?? resource)
                guard !Task.isCancelled, tasks[id] != nil else { return }
                let mime = UTType(filenameExtension: requested.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                urlSchemeTask.didReceive(URLResponse(url: requested, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                if !Task.isCancelled, tasks[id] != nil { urlSchemeTask.didFailWithError(error) }
            }
            tasks[id] = nil
        }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}

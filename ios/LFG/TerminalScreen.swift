import SwiftUI
import SwiftTerm
import LFGCore

/// A shell on a host, over `/api/term` through the same tunnel + Access
/// credential as the rest of the API. The server attaches each socket to a
/// persistent tmux session, so closing this screen (or backgrounding the app)
/// only detaches: reopening lands back in the same shell.
struct TerminalScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// One shared shell name across iOS devices, so the iPad picks up where the
    /// phone left off.
    static let sessionName = "phone"
    /// Board `s2-terminal`: the screen behind the terminal.
    static let background = SwiftUI.Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255)
    /// The close button and the Fit / Wide track. The board writes
    /// `rgba(255,255,255,0.12)` over the page; the canvas draws that as #313132,
    /// brighter than SwiftUI's blend of the same values (#28282A), so this uses
    /// the colour the design shows.
    static let chromeFill = SwiftUI.Color(red: 49 / 255, green: 49 / 255, blue: 50 / 255)

    @State private var hostURL: String?
    @State private var controller: TerminalController?
    @State private var wideTerminal = false

    /// `initialHostURL` opens on that host (a session's host, from its menu);
    /// nil uses the default host.
    init(initialHostURL: String? = nil) {
        _hostURL = State(initialValue: initialHostURL)
    }

    private var host: Host? {
        settings.hosts.first { $0.url == hostURL }
            ?? settings.hosts.first(where: \.isDefault)
            ?? settings.hosts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // In the stack, not overlaid: an overlay covered the top lines of output.
            if let controller, case .disconnected(let reason) = controller.phase {
                disconnectedBanner(reason, controller: controller)
            }
            ZStack(alignment: .top) {
                Self.background
                if let controller {
                    TerminalHostingView(controller: controller)
                        // A new controller (host switch) must get a new UIView:
                        // makeUIView runs once per identity, so without this the
                        // old host's dead terminal stayed on screen.
                        .id(ObjectIdentifier(controller))
                        // Board: the output sits 10pt below the header, 12pt in
                        // from each side and 10pt above the key row.
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    if controller.phase == .connecting {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 12)
                            .accessibilityIdentifier("terminalConnecting")
                    }
                } else {
                    Text("Add a host in Settings to open a terminal.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
        }
        .background(Self.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: host?.url) { openController() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: controller?.detach()
            case .active: controller?.resumeIfDetached()
            default: break
            }
        }
        .onDisappear { controller?.detach() }
    }

    /// A plain header instead of a navigation bar, as in the session list: system
    /// toolbar items never reach the accessibility tree here, so automation (and
    /// VoiceOver) couldn't find Close. Board `s2-terminal`: close, "Terminal ·
    /// Shell on Pro", and a Fit / Wide switch.
    private var header: some View {
        HStack(spacing: 8) {
            Button {
                controller?.detach()
                dismiss()
            } label: {
                SheetGlyph(kind: .close)
                    .stroke(SwiftUI.Color.white, style: StrokeStyle(lineWidth: 2.6 * 15 / 24, lineCap: .round))
                    .frame(width: 15, height: 15)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Self.chromeFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("terminalCloseButton")

            title
                .frame(maxWidth: .infinity)

            widthSwitch
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    /// "Terminal" over "Shell on Pro". With several hosts it is also the host
    /// switch (the old separate host button).
    @ViewBuilder
    private var title: some View {
        let label = VStack(spacing: 1) {
            Text("Terminal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(S2.ink)
            Text("Shell on \(host?.label ?? "the host")")
                .font(.system(size: 12))
                .foregroundStyle(S2.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("terminalTitle")
        if settings.hosts.count > 1 {
            Menu {
                ForEach(settings.hosts) { h in
                    Button {
                        hostURL = h.url
                    } label: {
                        Label(h.disambiguatedLabel(among: settings.hosts),
                              systemImage: h.url == host?.url ? "checkmark" : "")
                    }
                }
            } label: { label }
                .buttonStyle(.plain)
                .accessibilityIdentifier("terminalHostMenu")
        } else {
            label
        }
    }

    /// Fit / Wide (board: a 92×32 pill, the chosen half white).
    private var widthSwitch: some View {
        HStack(spacing: 0) {
            widthOption("Fit", selected: !wideTerminal) { setWide(false) }
            widthOption("Wide", selected: wideTerminal) { setWide(true) }
        }
        .padding(2)
        .background(Capsule().fill(Self.chromeFill))
        .accessibilityIdentifier("terminalWidthButton")
    }

    private func widthOption(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? SwiftUI.Color.black : SwiftUI.Color.white)
                .frame(width: 44, height: 28)
                .background { if selected { Capsule().fill(SwiftUI.Color.white) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "Fit" ? "Fit terminal to screen" : "Show wide terminal")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setWide(_ wide: Bool) {
        guard wideTerminal != wide else { return }
        wideTerminal = wide
        controller?.setWideMode(wide)
    }

    private func openController() {
        controller?.detach()
        guard let host, let client = settings.client(for: host) else {
            controller = nil
            return
        }
        let next = TerminalController(client: client, sessionName: Self.sessionName)
        next.setWideMode(wideTerminal)
        controller = next
        next.connect()
    }

    private func disconnectedBanner(_ reason: TerminalDisconnect, controller: TerminalController) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
            Text(reason.message)
                .font(.footnote)
                .lineLimit(2)
                .accessibilityIdentifier("terminalDisconnectedMessage")
            Spacer(minLength: 8)
            Button("Reconnect") { controller.connect() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("terminalReconnectButton")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminalDisconnectedBanner")
    }
}

/// Owns the SwiftTerm view and the socket feeding it.
@MainActor
@Observable
final class TerminalController: NSObject {
    enum Phase: Equatable {
        case connecting
        case connected
        case disconnected(TerminalDisconnect)
        /// Detached on purpose (screen closed or app backgrounded).
        case detached
    }

    private(set) var phase: Phase = .detached

    @ObservationIgnored let terminalView: SwiftTerm.TerminalView
    @ObservationIgnored let viewport: TerminalViewportView
    @ObservationIgnored private let client: LFGClient
    @ObservationIgnored private let sessionName: String
    @ObservationIgnored private var socket: TerminalSocket?

    init(client: LFGClient, sessionName: String) {
        self.client = client
        self.sessionName = sessionName
        let view = SwiftTerm.TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        // Board `s2-terminal`: 12pt monospace on a 1.45 line, #D1D1D6 on #0B0B0D,
        // with a steady block caret in the text colour.
        view.font = Self.font(wide: false)
        view.lineHeightMultiple = 1.45
        let background = UIColor(red: 11 / 255, green: 11 / 255, blue: 13 / 255, alpha: 1)
        let ink = UIColor(red: 209 / 255, green: 209 / 255, blue: 214 / 255, alpha: 1)
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = ink
        view.backgroundColor = background
        view.getTerminal().setCursorStyle(.steadyBlock)
        view.accessibilityIdentifier = "terminalView"
        // Never forward touches as mouse events. tmux here runs with `mouse on`,
        // so a swipe became clicks and drags inside tmux, and one pasted a tmux
        // buffer (lfg's queued agent messages) into the shell.
        view.allowMouseReporting = false
        terminalView = view
        viewport = TerminalViewportView(terminalView: view)
        super.init()
        view.terminalDelegate = self
        view.caretColor = ink
        view.caretTextColor = background

        // Vertical drags scroll the transcript. The shell runs in tmux, so history
        // lives on the server; this view only ever holds the visible screen, and
        // its own UIScrollView pan had nothing to scroll.
        view.isScrollEnabled = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    // MARK: Transcript scrolling

    @ObservationIgnored private var scrollRemainder: CGFloat = 0
    @ObservationIgnored private var flingTask: Task<Void, Never>?

    /// Board: Fit is 12pt, Wide is 10.5pt, both on a 1.45 line and both fitted
    /// to the screen's width (Wide gains columns by shrinking the type).
    static func font(wide: Bool) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: wide ? 10.5 : 12, weight: .regular)
    }

    func setWideMode(_ wide: Bool) {
        let font = Self.font(wide: wide)
        guard terminalView.font.pointSize != font.pointSize else { return }
        terminalView.font = font
        // The row height changed, so the whole-row frame does too.
        viewport.setNeedsLayout()
    }

    private var rowHeight: CGFloat {
        let rows = max(1, terminalView.getTerminal().rows)
        return max(8, terminalView.bounds.height / CGFloat(rows))
    }

    @objc private func handleScrollPan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            flingTask?.cancel()
            scrollRemainder = 0
        case .changed:
            let delta = pan.translation(in: terminalView)
            pan.setTranslation(.zero, in: terminalView)
            // Finger down reveals older output, as in any scroll view.
            scrollBy(points: delta.y)
        case .ended:
            fling(velocity: pan.velocity(in: terminalView).y)
        default:
            break
        }
    }

    private func scrollBy(points: CGFloat) {
        scrollRemainder += points / rowHeight
        let lines = Int(scrollRemainder.rounded(.towardZero))
        guard lines != 0 else { return }
        scrollRemainder -= CGFloat(lines)
        socket?.scroll(lines: lines)
    }

    /// A short, decaying glide after a flick, sent in small steps.
    private func fling(velocity: CGFloat) {
        flingTask?.cancel()
        guard abs(velocity) > 300 else { return }
        flingTask = Task { @MainActor [weak self] in
            var v = velocity
            while abs(v) >= 60, !Task.isCancelled {
                self?.scrollBy(points: v / 30)
                v *= 0.88
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func connect() {
        socket?.disconnect()
        phase = .connecting
        let terminal = terminalView.getTerminal()
        // Callbacks on the main queue: each keystroke echo is its own chunk, and a
        // hop from URLSession's queue to main measured ~5ms per character.
        let socket = TerminalSocket(
            request: client.terminalRequest(session: sessionName, cols: terminal.cols, rows: terminal.rows),
            callbackQueue: .main)
        self.socket = socket

        socket.onOpen = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.socket === socket else { return }
                self.phase = .connected
                let t = self.terminalView.getTerminal()
                socket.resize(cols: t.cols, rows: t.rows)
            }
        }
        socket.onOutput = { [weak self] data in
            MainActor.assumeIsolated {
                guard let self, self.socket === socket else { return }
                self.terminalView.feed(byteArray: ArraySlice([UInt8](data)))
            }
        }
        socket.onDisconnect = { [weak self] reason in
            MainActor.assumeIsolated {
                guard let self, self.socket === socket else { return }
                self.socket = nil
                self.phase = .disconnected(reason)
            }
        }
        socket.connect()
    }

    func detach() {
        socket?.disconnect()
        socket = nil
        if phase != .detached { phase = .detached }
    }

    /// Back from the background: reattach only if we were detached by it, not
    /// if the user is looking at a disconnect banner they haven't acted on.
    func resumeIfDetached() {
        if phase == .detached { connect() }
    }
}

extension TerminalController: UIGestureRecognizerDelegate {
    /// Vertical drags only, and never while text is selected.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: terminalView)
        guard !terminalView.selectionActive else { return false }
        return abs(v.y) > abs(v.x)
    }

    /// SwiftTerm's own recognizers on the same view (the scroll view's pan, tap and
    /// long-press) otherwise keep this one from ever firing.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

extension TerminalController: @preconcurrency TerminalViewDelegate {
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        socket?.send(Data(data))
    }

    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        socket?.resize(cols: newCols, rows: newRows)
    }

    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        UIApplication.shared.open(url)
    }

    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        if let text = String(data: content, encoding: .utf8) { UIPasteboard.general.string = text }
    }

    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}

/// Holds the terminal at the viewport's size and clips it. The terminal's
/// bounds drive the PTY resize.
@MainActor
final class TerminalViewportView: UIView {
    let terminalView: SwiftTerm.TerminalView

    init(terminalView: SwiftTerm.TerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(terminalView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Whole rows only, sitting on the bottom edge: the part of a row that does
        // not fit goes above the first row, so the last row keeps the board's 10pt
        // above the key row. (+0.5 keeps float error from dropping a row.)
        var frame = bounds
        if let multiple = terminalView.lineHeightMultiple {
            let row = terminalView.font.pointSize * multiple
            let height = min(bounds.height, (bounds.height / row).rounded(.down) * row + 0.5)
            frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        }
        if terminalView.frame != frame { terminalView.frame = frame }
    }
}

/// Hosts the controller's long-lived SwiftTerm view, so a SwiftUI re-render never
/// recreates the terminal or loses its scrollback.
private struct TerminalHostingView: UIViewRepresentable {
    let controller: TerminalController

    func makeUIView(context: Context) -> TerminalViewportView {
        let viewport = controller.viewport
        DispatchQueue.main.async { _ = controller.terminalView.becomeFirstResponder() }
        return viewport
    }

    func updateUIView(_ uiView: TerminalViewportView, context: Context) {}
}

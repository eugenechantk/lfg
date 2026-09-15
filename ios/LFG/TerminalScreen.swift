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

    @State private var hostURL: String?
    @State private var controller: TerminalController?

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
                Color.black
                if let controller {
                    TerminalHostingView(controller: controller)
                        // A new controller (host switch) must get a new UIView:
                        // makeUIView runs once per identity, so without this the
                        // old host's dead terminal stayed on screen.
                        .id(ObjectIdentifier(controller))
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
        .background(Color.black.ignoresSafeArea())
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
    /// VoiceOver) couldn't find Close.
    private var header: some View {
        HStack(spacing: 10) {
            Button {
                controller?.detach()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassOrRaised(in: Circle(), fallback: Color(white: 0.16), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("terminalCloseButton")

            Spacer(minLength: 8)
            // Two lines, not "Terminal · name (host:port)": at iPhone width that
            // truncated away exactly the part that tells two hosts apart.
            VStack(spacing: 1) {
                Text(host?.label ?? "Terminal")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = host?.disambiguator(among: settings.hosts) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("terminalTitle")
            Spacer(minLength: 8)

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
                } label: {
                    Image(systemName: "server.rack")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .glassOrRaised(in: Circle(), fallback: Color(white: 0.16), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Host")
                .accessibilityIdentifier("terminalHostMenu")
            } else {
                // Same width as the close button, so the title stays centred.
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func openController() {
        controller?.detach()
        guard let host, let client = settings.client(for: host) else {
            controller = nil
            return
        }
        let next = TerminalController(client: client, sessionName: Self.sessionName)
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
    @ObservationIgnored private let client: LFGClient
    @ObservationIgnored private let sessionName: String
    @ObservationIgnored private var socket: TerminalSocket?

    init(client: LFGClient, sessionName: String) {
        self.client = client
        self.sessionName = sessionName
        let view = SwiftTerm.TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = UIColor(white: 0.92, alpha: 1)
        view.backgroundColor = .black
        view.accessibilityIdentifier = "terminalView"
        terminalView = view
        super.init()
        view.terminalDelegate = self
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

/// Hosts the controller's long-lived SwiftTerm view, so a SwiftUI re-render never
/// recreates the terminal or loses its scrollback.
private struct TerminalHostingView: UIViewRepresentable {
    let controller: TerminalController

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let view = controller.terminalView
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {}
}

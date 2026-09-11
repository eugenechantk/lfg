import SwiftUI
import UIKit
import LFGCore

@MainActor @Observable final class BrowserStreamConnection {
    var windows: [BrowserStreamWindow] = []
    var selected: BrowserStreamWindow?
    var image: UIImage?
    var connected = false
    var controlling = false
    var error: String?
    var frameID: Int?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var commands: [BrowserStreamCommand] = []
    private var sequence = 0
    private var generation = UUID()
    private var lastMessage = Date()
    private var firstFrameDeadline: Date?

    func connect(_ client: LFGClient) {
        disconnect()
        error = nil; windows = []; selected = nil; image = nil; frameID = nil
        let token = UUID(); generation = token
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        self.session = session
        let socket = session.webSocketTask(with: client.browserStreamRequest())
        socket.maximumMessageSize = 4 * 1024 * 1024
        self.socket = socket
        lastMessage = Date()
        socket.resume()
        receiveTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let incoming = try await socket.receive()
                    let data: Data
                    switch incoming {
                    case .string(let string): data = Data(string.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    let message = try JSONDecoder().decode(BrowserStreamMessage.self, from: data)
                    guard let self, self.generation == token else { return }
                    self.lastMessage = Date(); self.connected = true
                    switch message.type {
                    case "windows": self.windows = message.windows ?? []
                    case "frame":
                        guard message.windowId == self.selected?.id,
                              let jpeg = message.jpeg, let image = UIImage(data: jpeg), let id = message.frameId else { continue }
                        self.image = image; self.frameID = id; self.firstFrameDeadline = nil
                        self.enqueue(.init(type:"ack",frameId:id))
                    case "control": self.controlling = message.enabled == true
                    case "error": self.error = message.message ?? "Stream unavailable"; self.controlling = false
                    default: break
                    }
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail(self.error ?? "Connection lost. Reconnect to continue.")
            }
        }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(5))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                if let deadline = self.firstFrameDeadline, Date() > deadline {
                    self.fail("No video arrived. Unlock and wake the Mac, then reconnect."); return
                }
                if Date().timeIntervalSince(self.lastMessage) > 15 {
                    self.fail("The Mac stopped responding. Reconnect to continue."); return
                }
                self.enqueue(.init(type:"ping"))
            }
        }
    }
    func disconnect() {
        generation = UUID()
        controlling = false; connected = false
        commands.removeAll(); sendTask?.cancel(); sendTask = nil
        receiveTask?.cancel(); receiveTask = nil; heartbeat?.cancel(); heartbeat = nil
        socket?.cancel(with:.goingAway,reason:nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        image = nil; frameID = nil; firstFrameDeadline = nil
    }
    private func fail(_ message: String) { disconnect(); error = message }
    func select(_ window: BrowserStreamWindow) {
        controlling = false; image = nil; frameID = nil; error = nil; selected = window
        firstFrameDeadline = Date().addingTimeInterval(10)
        enqueue(.init(type:"select",windowId:window.id))
    }
    func control(_ enabled: Bool) {
        error = nil
        if !enabled { controlling = false }
        enqueue(.init(type:"control",enabled:enabled))
    }
    func input(_ command: BrowserStreamCommand) {
        guard controlling, connected, let frameID else { return }
        sequence += 1
        var command = command; command.seq = sequence; command.frameId = frameID
        enqueue(command)
    }
    private func enqueue(_ command: BrowserStreamCommand) {
        guard socket != nil else { return }
        // Never let disconnected/slow networking retain an unbounded input backlog.
        guard commands.count < 64 else { fail("Connection too slow for input. Reconnect to continue."); return }
        commands.append(command)
        guard sendTask == nil else { return }
        let token = generation
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.sendTask = nil } }
            do {
                while !self.commands.isEmpty, !Task.isCancelled, self.generation == token {
                    let next = self.commands.removeFirst()
                    let data = try JSONEncoder().encode(next)
                    guard let string = String(data:data,encoding:.utf8), let socket = self.socket else { return }
                    try await socket.send(.string(string))
                }
            } catch {
                if self.generation == token { self.fail("Input delivery failed. Check the page before retrying.") }
            }
        }
    }
}

struct BrowserStreamView: View {
    let sessionID: String
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var connection = BrowserStreamConnection()
    @State private var text = ""
    @State private var showControlNotice = false
    @State private var interaction = 0
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let error = connection.error {
                    VStack(spacing:8) {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("browser_stream_error")
                        if !connection.connected {
                            Button("Reconnect",action:connect)
                                .accessibilityIdentifier("browser_stream_reconnect")
                        }
                    }.padding(.horizontal)
                }
                if let window = connection.selected {
                    HStack {
                        VStack(alignment:.leading) {
                            Text(window.app).font(.headline)
                            Text(window.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(connection.connected ? (connection.controlling ? "Controlling" : "Viewing") : "Disconnected")
                            .font(.caption).foregroundStyle(connection.controlling ? Color.orange : Color.secondary)
                    }.padding(.horizontal)
                    GeometryReader { geometry in
                        ZStack {
                            Color.black
                            if let image = connection.image {
                                let size = fitted(image.size, in: geometry.size)
                                RemotePointerSurface(image:image,enabled:connection.controlling,scrolling:interaction == 1) { command in
                                    connection.input(command)
                                }
                                .frame(width:size.width,height:size.height)
                                .clipped()
                                .accessibilityIdentifier("browser_stream_surface")
                            } else if connection.connected {
                                ProgressView("Starting stream…").tint(.white).foregroundStyle(.white)
                            }
                        }.clipped()
                    }
                    HStack {
                        Picker("Pointer mode",selection:$interaction) {
                            Text("Mouse").tag(0)
                            Text("Scroll").tag(1)
                        }.pickerStyle(.segmented).accessibilityIdentifier("browser_stream_pointer_mode")
                        Button(connection.controlling ? "Stop control" : "Control") {
                            if connection.controlling { connection.control(false); text = ""; keyboardFocused = false }
                            else { showControlNotice = true }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!connection.connected || connection.image == nil)
                        .accessibilityIdentifier("browser_stream_control")
                    }.padding(.horizontal)
                    if connection.controlling {
                        HStack(spacing:8) {
                            SecureField("Type text on Mac",text:$text)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($keyboardFocused)
                                .onSubmit(sendText)
                                .accessibilityIdentifier("browser_stream_text")
                            Button("Type",action:sendText).disabled(text.isEmpty)
                                .accessibilityIdentifier("browser_stream_type")
                        }.padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal)
                        ScrollView(.horizontal) {
                            HStack(spacing:12) {
                                key("Tab","tab"); key("Enter","enter"); key("⌫","backspace")
                                key("Esc","escape"); key("Select all","selectAll")
                                key("←","left"); key("→","right"); key("↑","up"); key("↓","down")
                            }.padding(.horizontal)
                        }.scrollIndicators(.hidden)
                    } else {
                        Text("Tap Control to use the mouse and keyboard.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if connection.connected && connection.error == nil {
                    List {
                        Section("Choose a window on \(store.host(forSession:sessionID)?.label ?? "your Mac")") {
                            ForEach(connection.windows) { window in
                                Button { connection.select(window) } label: {
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(window.app).font(.headline).foregroundStyle(.primary)
                                        Text(window.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }.buttonStyle(.plain).accessibilityIdentifier("browser_stream_window_\(window.id)")
                            }
                            if connection.windows.isEmpty { Text("No windows available. Open Chrome on the Mac, then reconnect.") }
                        }
                    }.listStyle(.insetGrouped).accessibilityIdentifier("browser_stream_windows")
                } else if connection.error == nil {
                    Spacer(); ProgressView("Connecting to Mac…"); Spacer()
                } else { Spacer() }
            }
            .padding(.bottom,12)
            .navigationTitle("Browser Stream").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Done") { connection.disconnect(); text = ""; dismiss() }
                        .accessibilityIdentifier("browser_stream_done")
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button("Windows") { text = ""; keyboardFocused = false; connect() }
                        .accessibilityIdentifier("browser_stream_choose_window")
                }
            }
            .confirmationDialog("Control this Mac?",isPresented:$showControlNotice,titleVisibility:.visible) {
                Button("Enable control") { connection.control(true) }
                    .accessibilityIdentifier("browser_stream_enable_control")
            } message: {
                Text("Pause browser automation first. Mouse and keyboard input act on the selected Mac window. This does not pause or resume the agent.")
            }
        }
        .accessibilityIdentifier("browser_stream_view")
        .task { connect() }
        .onDisappear { text = ""; connection.disconnect() }
        .onChange(of: connection.controlling) { _, enabled in
            if !enabled { text = ""; keyboardFocused = false }
        }
        .onChange(of:scenePhase) { _, phase in
            if phase != .active { text = ""; keyboardFocused = false; connection.disconnect() }
            else if !connection.connected { connection.error = "Stream paused while the app was inactive. Reconnect to continue." }
        }
    }
    private func connect() {
        guard let host = store.host(forSession: sessionID), let client = settings.client(for: host) else {
            connection.error = "The session's Mac is unavailable."; return
        }
        connection.connect(client)
    }
    private func sendText() {
        guard !text.isEmpty else { return }
        guard text.utf8.count <= 4096 else { connection.error = "Send text in smaller chunks (up to 4 KB)."; return }
        connection.input(.init(type:"text",text:text)); text = ""
    }
    private func key(_ title: String, _ key: String) -> some View {
        Button(title) { connection.input(.init(type:"key",key:key)) }
            .buttonStyle(.bordered).accessibilityIdentifier("browser_stream_key_\(key)")
    }
    private func fitted(_ image: CGSize, in container: CGSize) -> CGSize {
        let scale = min(container.width/max(image.width,1),container.height/max(image.height,1))
        return CGSize(width:image.width*scale,height:image.height*scale)
    }
}

/// The image view's bounds are exactly the streamed rectangle (no letterbox input).
private struct RemotePointerSurface: UIViewRepresentable {
    let image: UIImage
    let enabled: Bool
    let scrolling: Bool
    let send: (BrowserStreamCommand) -> Void
    func makeUIView(context:Context) -> RemotePointerView { RemotePointerView(frame: .zero) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RemotePointerView, context: Context) -> CGSize? {
        // UIImageView's intrinsic pixel dimensions must not override SwiftUI's
        // fitted point rectangle, otherwise taps and the visible image diverge.
        CGSize(width: proposal.width ?? 1, height: proposal.height ?? 1)
    }
    func updateUIView(_ view:RemotePointerView,context:Context) {
        if view.scrolling != scrolling || !enabled { view.releasePointer() }
        view.image = image; view.isUserInteractionEnabled = enabled
        view.scrolling = scrolling; view.send = send
    }
}
private final class RemotePointerView: UIImageView {
    var scrolling = false
    var send: ((BrowserStreamCommand)->Void)?
    private var previous = CGPoint.zero
    private var pressed = false
    private var lastMove = Date.distantPast
    override init(frame:CGRect) {
        super.init(frame:frame); contentMode = .scaleToFill; isMultipleTouchEnabled = false
        let long = UILongPressGestureRecognizer(target:self,action:#selector(rightClick(_:)))
        long.minimumPressDuration = 0.6; addGestureRecognizer(long)
        let hover = UIHoverGestureRecognizer(target:self,action:#selector(hover(_:))); addGestureRecognizer(hover)
    }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func command(_ action:String, at point:CGPoint, button:String = "left") {
        guard bounds.width > 0, bounds.height > 0 else { return }
        send?(.init(type:"pointer",action:action,button:button,
                    x:Double(min(max(point.x/bounds.width,0),1)),y:Double(min(max(point.y/bounds.height,0),1))))
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let point = touches.first?.location(in:self) else { return }; previous = point
        if !scrolling { pressed = true; command("down",at:point) }
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let point = touches.first?.location(in:self), Date().timeIntervalSince(lastMove)>0.03 else { return }
        lastMove = Date()
        if scrolling {
            send?(.init(type:"scroll",x:Double(min(max(point.x/max(bounds.width,1),0),1)),
                        y:Double(min(max(point.y/max(bounds.height,1),0),1)),dy:Double(max(-1000,min(1000,(point.y-previous.y)*3)))))
        } else { command("move",at:point) }
        previous = point
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        previous = touches.first?.location(in:self) ?? previous
        releasePointer()
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) {
        releasePointer()
    }
    func releasePointer() {
        if pressed { command("up",at:previous); pressed = false }
    }
    @objc private func rightClick(_ gesture:UILongPressGestureRecognizer) {
        guard gesture.state == .began, !scrolling else { return }
        releasePointer()
        command("down",at:gesture.location(in:self),button:"right")
        command("up",at:gesture.location(in:self),button:"right")
    }
    @objc private func hover(_ gesture:UIHoverGestureRecognizer) {
        guard !scrolling, Date().timeIntervalSince(lastMove)>0.03 else { return }
        lastMove = Date(); command("move",at:gesture.location(in:self))
    }
}

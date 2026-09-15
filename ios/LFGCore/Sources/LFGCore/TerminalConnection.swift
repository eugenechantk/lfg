import Foundation

/// Control frames for `/api/term`. Keystrokes travel as binary frames; text frames
/// are JSON control messages (see the websocket handler in `src/commands/serve.ts`).
public enum TerminalControl {
    /// The server clamps each dimension to 1...500; clamp here so the pty and the
    /// local renderer never disagree about the size.
    public static func clamp(_ value: Int) -> Int { min(500, max(1, value)) }

    public static func resize(cols: Int, rows: Int) -> String {
        #"{"t":"resize","cols":\#(clamp(cols)),"rows":\#(clamp(rows))}"#
    }
}

/// Why a terminal socket ended, in the terms the UI shows.
public enum TerminalDisconnect: Equatable, Sendable {
    /// The server closed cleanly: the attach client exited (e.g. `exit` in the shell).
    case shellExited
    /// Cloudflare Access or the server's Access check refused the upgrade.
    case forbidden
    /// Transport loss: tunnel dropped, app backgrounded, server restarted.
    case network(String?)

    public init(closeCode: URLSessionWebSocketTask.CloseCode, error: String?) {
        self = closeCode == .normalClosure ? .shellExited : .network(error)
    }

    public init(httpStatus: Int) {
        self = (httpStatus == 401 || httpStatus == 403) ? .forbidden : .network("HTTP \(httpStatus)")
    }

    public var message: String {
        switch self {
        case .shellExited: return "Shell exited"
        case .forbidden: return "Access denied — check this host's Cloudflare Access credential"
        // The system error text ("The operation couldn't be completed. Socket is
        // not connected") says nothing a person can act on, so it isn't shown.
        case .network: return "Connection lost"
        }
    }
}

extension Host {
    /// `label`, plus host:port when another configured host shares the label: the
    /// same machine reached by two URLs reports one hostname for both.
    public func disambiguatedLabel(among hosts: [Host]) -> String {
        disambiguator(among: hosts).map { "\(label) (\($0))" } ?? label
    }

    /// host[:port] from the URL, but only when another host shares `label`.
    public func disambiguator(among hosts: [Host]) -> String? {
        guard hosts.contains(where: { $0.url != url && $0.label == label }),
              let parsed = URL(string: url.contains("://") ? url : "http://\(url)"),
              let name = parsed.host else { return nil }
        return parsed.port.map { "\(name):\($0)" } ?? name
    }
}

extension LFGClient {
    /// The websocket request for `/api/term`: the host's base URL with ws/wss in
    /// place of http/https, plus the host's Access credential.
    public func terminalRequest(session: String, cols: Int, rows: Int) -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/term"), resolvingAgainstBaseURL: false)
            ?? URLComponents()
        switch comps.scheme?.lowercased() {
        case "https": comps.scheme = "wss"
        case "http": comps.scheme = "ws"
        default: break
        }
        comps.queryItems = [
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "cols", value: String(TerminalControl.clamp(cols))),
            URLQueryItem(name: "rows", value: String(TerminalControl.clamp(rows))),
        ]
        var request = URLRequest(url: comps.url ?? baseURL)
        applyAccessCredential(to: &request)
        return request
    }
}

/// One `/api/term` websocket. Callbacks fire on `callbackQueue` (pass `.main` from
/// UI code to skip a queue hop per output chunk: every keystroke echo is one). Reconnecting means making a new socket, and
/// the server's tmux session keeps the shell alive in between.
public final class TerminalSocket: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    public var onOutput: (@Sendable (Data) -> Void)?
    public var onOpen: (@Sendable () -> Void)?
    public var onDisconnect: (@Sendable (TerminalDisconnect) -> Void)?

    private let request: URLRequest
    private let callbackQueue: OperationQueue?
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var finished = false

    public init(request: URLRequest, callbackQueue: OperationQueue? = nil) {
        self.request = request
        self.callbackQueue = callbackQueue
    }

    public func connect() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: callbackQueue)
        let task = session.webSocketTask(with: request)
        // Output bursts (a full-screen repaint) can be large.
        task.maximumMessageSize = 4 * 1024 * 1024
        lock.withLock {
            self.session = session
            self.task = task
            finished = false
        }
        task.resume()
        receive(on: task)
    }

    public func send(_ bytes: Data) {
        currentTask()?.send(.data(bytes)) { _ in }
    }

    public func resize(cols: Int, rows: Int) {
        currentTask()?.send(.string(TerminalControl.resize(cols: cols, rows: rows))) { _ in }
    }

    /// Detach on purpose. Does not report a disconnect.
    public func disconnect() {
        let (task, session) = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?) in
            finished = true
            defer { self.task = nil; self.session = nil }
            return (self.task, self.session)
        }
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }

    private func currentTask() -> URLSessionWebSocketTask? {
        lock.withLock { finished ? nil : task }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                self.onOutput?(data)
                self.receive(on: task)
            case .success(.string(let text)):
                // The server sends a text frame only for its own error notes.
                self.onOutput?(Data(text.utf8))
                self.receive(on: task)
            case .success:
                self.receive(on: task)
            case .failure(let error):
                let status = (task.response as? HTTPURLResponse)?.statusCode
                if let status, status >= 400 {
                    self.finish(TerminalDisconnect(httpStatus: status))
                } else {
                    self.finish(TerminalDisconnect(closeCode: task.closeCode, error: error.localizedDescription))
                }
            }
        }
    }

    private func finish(_ reason: TerminalDisconnect) {
        let shouldReport = lock.withLock { () -> Bool in
            if finished { return false }
            finished = true
            return true
        }
        guard shouldReport else { return }
        onDisconnect?(reason)
        lock.withLock { session }?.finishTasksAndInvalidate()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        onOpen?()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(TerminalDisconnect(closeCode: closeCode, error: nil))
    }
}

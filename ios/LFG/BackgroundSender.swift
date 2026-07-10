import Foundation
import UIKit
import LFGCore
import os

/// Sends session messages over a **background URLSession** so the transfer is
/// completed by the system even if the app is suspended or killed mid-POST —
/// Phase 2 Task C (`.claude/feature/phase2-background-continuity.md`).
///
/// Shape: the caller awaits `post(...)` exactly like a normal request — while
/// the app lives, the continuation resolves from the delegate callbacks and
/// the store's existing delivered/failed handling runs unchanged. If the app
/// dies, the continuation dies with it but the SYSTEM still finishes the POST
/// (that's the whole point); the outcome is then reconciled from server state
/// (queue + transcript) exactly like every other optimistic-send repair path.
///
/// Background-session constraints honored here: uploads must be file-based
/// (bodies are written under caches/lfg-bgsend and deleted on completion) and
/// the session needs a delegate object that survives for the app's lifetime
/// (`shared`). `handleEventsForBackgroundURLSession` re-creates this session
/// after a relaunch-from-kill; orphaned body files are pruned at startup.
@MainActor
final class BackgroundSender: NSObject {
    static let shared = BackgroundSender()

    static let sessionIdentifier = "com.eugenechan.lfg.send"

    private let log = Logger(subsystem: "dev.omg.lfg", category: "bgsend")
    private var session: URLSession!
    /// taskIdentifier → in-flight state (response buffer + caller continuation).
    private var inflight: [Int: Inflight] = [:]
    /// Stashed from handleEventsForBackgroundURLSession; called once the
    /// session drains after a background relaunch.
    var systemCompletionHandler: (() -> Void)?

    private struct Inflight {
        var buffer = Data()
        var continuation: CheckedContinuation<Data, Error>?
        var bodyFile: URL?
    }

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        cfg.isDiscretionary = false          // user-initiated sends: start now
        cfg.sessionSendsLaunchEvents = true  // relaunch us to report the outcome
        session = URLSession(configuration: cfg, delegate: Delegate(owner: self), delegateQueue: nil)
        pruneOrphanBodyFiles()
    }

    private var bodyDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lfg-bgsend", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Bodies whose task no longer exists (completed while we were dead, or a
    /// stale crash leftover). The transfer itself was the system's job; the
    /// bubble outcome is reconciled from server state, so the file is just litter.
    private func pruneOrphanBodyFiles() {
        Task { [weak self] in
            guard let self else { return }
            let live = await session.allTasks.compactMap { $0.taskDescription }
            let fm = FileManager.default
            for f in (try? fm.contentsOfDirectory(at: bodyDir, includingPropertiesForKeys: nil)) ?? [] {
                if !live.contains(f.lastPathComponent) { try? fm.removeItem(at: f) }
            }
        }
    }

    /// POST a prepared request through the background session and await the
    /// response body. `label` names the body file and taskDescription (use the
    /// pending-send id so transfers are attributable in diagnostics).
    func post(_ request: URLRequest, label: String) async throws -> Data {
        let body = request.httpBody ?? Data()
        var req = request
        req.httpBody = nil
        let file = bodyDir.appendingPathComponent(label)
        try body.write(to: file, options: .atomic)
        let task = session.uploadTask(with: req, fromFile: file)
        task.taskDescription = label
        return try await withCheckedThrowingContinuation { cont in
            inflight[task.taskIdentifier] = Inflight(continuation: cont, bodyFile: file)
            task.resume()
        }
    }

    // MARK: delegate plumbing (hops from the session queue to the main actor)

    fileprivate func received(_ data: Data, taskId: Int) {
        inflight[taskId]?.buffer.append(data)
    }

    fileprivate func completed(taskId: Int, response: URLResponse?, error: Error?) {
        guard var state = inflight.removeValue(forKey: taskId) else {
            // Completed after a relaunch-from-kill: no caller is waiting; the
            // outcome lives on the server and the reconcile paths absorb it.
            log.notice("bg send finished with no awaiting caller (relaunch case)")
            return
        }
        if let f = state.bodyFile { try? FileManager.default.removeItem(at: f) }
        if let error {
            state.continuation?.resume(throwing: LFGError.notReachable(underlying: error.localizedDescription))
            return
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            state.continuation?.resume(throwing: LFGError.http(
                status: http.statusCode,
                body: String(data: state.buffer, encoding: .utf8) ?? ""))
            return
        }
        state.continuation?.resume(returning: state.buffer)
    }

    fileprivate func didFinishBackgroundEvents() {
        systemCompletionHandler?()
        systemCompletionHandler = nil
    }

    /// URLSession delegates arrive on a background queue; this shim forwards
    /// them onto the main actor. Kept separate so BackgroundSender itself can
    /// stay @MainActor without nonisolated escape hatches.
    private final class Delegate: NSObject, URLSessionDataDelegate {
        weak var owner: BackgroundSender?
        init(owner: BackgroundSender) { self.owner = owner }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let id = dataTask.taskIdentifier
            Task { @MainActor [weak owner] in owner?.received(data, taskId: id) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let id = task.taskIdentifier
            let resp = task.response
            Task { @MainActor [weak owner] in owner?.completed(taskId: id, response: resp, error: error) }
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            Task { @MainActor [weak owner] in owner?.didFinishBackgroundEvents() }
        }
    }
}

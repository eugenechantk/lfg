import Foundation

/// What we actually learned when a send threw.
///
/// The distinction the old code lacked: a throw can mean "the host read your
/// message and refused it" or "we stopped listening and have no idea what the
/// host did". Those look identical at the `catch` and mean opposite things.
public enum SendFailureEvidence: Equatable, Sendable {
    /// The host answered with a non-2xx status. Whatever went wrong, the server
    /// *formed an opinion* — this is real, attributable news.
    case serverAnswered(status: Int)
    /// URLSession gave up. `urlErrorCode` is `URLError.Code.rawValue` when it
    /// could be recovered; `nil` means even the reason is unknown.
    case transportFailed(urlErrorCode: Int?)
    /// The request could not be formed at all (no client, bad URL). Nothing was
    /// transmitted and nothing will be without the user acting.
    case unsendable
}

public extension SendFailureEvidence {
    /// Read the evidence out of whatever the send path threw.
    ///
    /// `LFGError.notReachable` and `.decoding` both land on "unknown code",
    /// which resolves to `.confirming` — correct in both cases. `.decoding`
    /// especially: a body we could not parse means the host *answered*, so the
    /// message very likely landed.
    static func from(_ error: Error?) -> SendFailureEvidence {
        switch error {
        case let e as LFGError:
            switch e {
            case .http(let status, _): return .serverAnswered(status: status)
            case .transport(let code, _): return .transportFailed(urlErrorCode: code)
            case .badURL: return .unsendable
            case .notReachable, .decoding, .streamStalled:
                return .transportFailed(urlErrorCode: nil)
            }
        case let e as URLError:
            return .transportFailed(urlErrorCode: e.code.rawValue)
        default:
            return .transportFailed(urlErrorCode: nil)
        }
    }
}

/// How to treat a send that threw.
public enum SendOutcomeClass: Equatable, Sendable {
    /// The message is not going. Hand it back with a banner.
    case terminal
    /// The request bytes went out and we never heard the answer. It may well
    /// have landed. Show nothing alarming and go find out.
    case confirming
    /// Still going by itself — offline queue or replayable attachments. Silent.
    case requeue
}

public enum SendTerminalityPolicy {

    /// URLError codes that leave delivery genuinely unknown.
    ///
    /// Each of these can fire **after the request body has been written to the
    /// wire**, so the host may have processed the message completely and only
    /// the response was lost. `timedOut` is the one Eugene hits daily: the first
    /// send over a cold tailnet path times out client-side, the server handles
    /// it fine, and the turn arrives over SSE a few seconds later — by which
    /// point the client had already declared "Not sent".
    public static let ambiguousTransportCodes: Set<Int> = [
        -1001,  // .timedOut
        -1005,  // .networkConnectionLost
        -999,   // .cancelled
    ]

    /// - Parameters:
    ///   - evidence: what the failure actually told us.
    ///   - hostStillDown: the owning host is not live. Nothing was sent and the
    ///     drain owns it — unchanged behaviour, and it outranks everything.
    ///   - hasAttachments: sidecar bytes are on disk, so the send is replayable
    ///     regardless of why it threw.
    ///
    /// The rule in one line: **only the server may declare a message dead.**
    /// Everything else is either self-recovering or unknown, and unknown is a
    /// question, not an answer.
    public static func classify(
        evidence: SendFailureEvidence,
        hostStillDown: Bool,
        hasAttachments: Bool
    ) -> SendOutcomeClass {
        if hostStillDown || hasAttachments { return .requeue }
        switch evidence {
        case .serverAnswered, .unsendable:
            return .terminal
        case .transportFailed(let code):
            // An unrecoverable code is still not knowledge. Defaulting the
            // unknown case to `.confirming` costs a few seconds of a queued
            // chip; defaulting it to `.terminal` is precisely the bug — a
            // delivered message reported as lost.
            guard let code else { return .confirming }
            return ambiguousTransportCodes.contains(code) ? .confirming : .terminal
        }
    }
}

/// What to do at each step of confirming an ambiguous send.
public enum DeliveryProbeAction: Equatable, Sendable {
    /// The turn (or its queue entry) is on the host. Mark it sent and retire the
    /// outbox row — no banner ever existed.
    case resolveDelivered
    case probeAgain(afterMs: Double)
    /// The window closed with no sign of it. NOW it is terminal, and now the
    /// banner is honest.
    case declareTerminal
}

/// The bounded "did it actually land?" window.
///
/// Bounded on purpose: an unbounded confirm would leave a message in limbo
/// forever, which is the failure mode in the other direction. Three probes over
/// ~15s covers the observed case (the turn arrives within a couple of seconds of
/// the client-side timeout) without making a genuinely-lost message wait long
/// for its Retry button.
public enum DeliveryConfirmationPolicy {
    public static let maxProbes = 3
    public static let probeIntervalMs: Double = 5_000
    public static var windowMs: Double { Double(maxProbes) * probeIntervalMs }

    /// - Parameters:
    ///   - probesCompleted: how many probes have already run and come back empty.
    ///   - foundDelivered: this probe found the message on the host — in the
    ///     session's outbound queue or as a real user turn in the transcript.
    ///     Either counts: the queue means the host took custody.
    public static func next(
        probesCompleted: Int,
        foundDelivered: Bool,
        maxProbes: Int = maxProbes,
        probeIntervalMs: Double = probeIntervalMs
    ) -> DeliveryProbeAction {
        if foundDelivered { return .resolveDelivered }
        if probesCompleted >= maxProbes { return .declareTerminal }
        return .probeAgain(afterMs: probeIntervalMs)
    }
}

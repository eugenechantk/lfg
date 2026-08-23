import XCTest
@testable import LFGCore

/// The four scenarios Eugene named, plus the boundaries around them.
///
/// Background: a cold-tunnel send times out client-side *after* the request
/// bytes went out. The server processes it, the turn arrives over SSE seconds
/// later and the bubble resolves cleanly — but a "Not sent" banner had already
/// fired. Terminality was being declared on evidence that said nothing.
final class SendTerminalityTests: XCTestCase {

    private let timedOut = SendFailureEvidence.transportFailed(urlErrorCode: -1001)
    private let connectionLost = SendFailureEvidence.transportFailed(urlErrorCode: -1005)
    private let cancelled = SendFailureEvidence.transportFailed(urlErrorCode: -999)

    private func classify(
        _ evidence: SendFailureEvidence,
        hostStillDown: Bool = false,
        hasAttachments: Bool = false
    ) -> SendOutcomeClass {
        SendTerminalityPolicy.classify(
            evidence: evidence,
            hostStillDown: hostStillDown,
            hasAttachments: hasAttachments)
    }

    // MARK: 1 — server error

    /// The host answered. That is the only evidence that justifies telling the
    /// user their message is dead.
    func testServerAnsweredIsImmediatelyTerminal() {
        for status in [400, 404, 409, 422, 500, 502, 503] {
            XCTAssertEqual(classify(.serverAnswered(status: status)), .terminal, "status=\(status)")
        }
    }

    // MARK: 2 — timeout (then delivered / then lost)

    /// The daily case. A timeout against a REACHABLE host must not be terminal:
    /// the request may have been processed in full.
    func testTimeoutAgainstReachableHostConfirmsRatherThanFails() {
        XCTAssertEqual(classify(timedOut), .confirming)
        XCTAssertEqual(classify(connectionLost), .confirming)
        XCTAssertEqual(classify(cancelled), .confirming)
    }

    /// Timeout → the probe finds the turn. Resolve silently; no banner was ever
    /// shown, and none is shown now.
    func testTimeoutThenDeliveredResolvesWithoutABanner() {
        XCTAssertEqual(classify(timedOut), .confirming)
        XCTAssertEqual(
            DeliveryConfirmationPolicy.next(probesCompleted: 0, foundDelivered: true),
            .resolveDelivered)
        XCTAssertEqual(
            DeliveryConfirmationPolicy.next(probesCompleted: 2, foundDelivered: true),
            .resolveDelivered,
            "a late confirmation still resolves — arriving on the last probe is a success")
    }

    /// Timeout → nothing ever shows up. The window closes and the user is told,
    /// once. Confirming delays the banner; it must not suppress it.
    func testTimeoutThenTrulyLostBecomesTerminalAtTheEndOfTheWindow() {
        XCTAssertEqual(classify(timedOut), .confirming)
        var probes = 0
        var actions: [DeliveryProbeAction] = []
        while true {
            let action = DeliveryConfirmationPolicy.next(
                probesCompleted: probes, foundDelivered: false)
            actions.append(action)
            if case .probeAgain = action { probes += 1; continue }
            break
        }
        XCTAssertEqual(probes, DeliveryConfirmationPolicy.maxProbes)
        XCTAssertEqual(actions.last, .declareTerminal)
        XCTAssertEqual(
            actions.dropLast(),
            Array(repeating: .probeAgain(afterMs: DeliveryConfirmationPolicy.probeIntervalMs),
                  count: DeliveryConfirmationPolicy.maxProbes))
    }

    /// The window has to actually close. An unbounded confirm strands the
    /// message with no Retry, which is the same bug pointed the other way.
    func testConfirmWindowIsBounded() {
        XCTAssertLessThanOrEqual(DeliveryConfirmationPolicy.windowMs, 30_000)
        XCTAssertGreaterThanOrEqual(DeliveryConfirmationPolicy.windowMs, 5_000)
    }

    // MARK: 3 — host down

    /// Unchanged, and it outranks the evidence: nothing left the phone, the
    /// drain owns it, and the queued bubble already says so.
    func testHostDownRequeuesRegardlessOfEvidence() {
        XCTAssertEqual(classify(timedOut, hostStillDown: true), .requeue)
        XCTAssertEqual(classify(.serverAnswered(status: 500), hostStillDown: true), .requeue)
        XCTAssertEqual(
            classify(.transportFailed(urlErrorCode: nil), hostStillDown: true), .requeue)
    }

    /// Attachment sidecars are on disk, so the send is replayable whatever
    /// happened — and burning the row would strand the bytes.
    func testAttachmentsRequeueRegardlessOfEvidence() {
        XCTAssertEqual(classify(timedOut, hasAttachments: true), .requeue)
        XCTAssertEqual(classify(.serverAnswered(status: 400), hasAttachments: true), .requeue)
    }

    // MARK: 4 — unambiguous transport failures

    /// DNS/connect failures never wrote a request body, so nothing can have
    /// landed — with a host we believe is up, that is real news.
    func testUnambiguousTransportFailuresStayTerminal() {
        for code in [-1003 /* cannotFindHost */, -1004 /* cannotConnectToHost */,
                     -1006 /* dnsLookupFailed */, -1009 /* notConnectedToInternet */] {
            XCTAssertEqual(
                classify(.transportFailed(urlErrorCode: code)), .terminal, "code=\(code)")
        }
    }

    /// "We could not even tell why" is not evidence of failure. Defaulting the
    /// unknown case to terminal is exactly the reported bug; it costs a few
    /// seconds of a queued chip to be right instead.
    func testUnknownTransportCodeConfirmsRatherThanFails() {
        XCTAssertEqual(classify(.transportFailed(urlErrorCode: nil)), .confirming)
    }

    // MARK: Reading the evidence off the thrown error

    /// The wiring the whole fix hangs on: `BackgroundSender` used to flatten a
    /// `URLError` into a string, so the code the classifier needs was gone by
    /// the time anything could look at it.
    func testEvidenceIsReadFromTheThrownError() {
        XCTAssertEqual(
            SendFailureEvidence.from(LFGError.http(status: 409, body: "{}")),
            .serverAnswered(status: 409))
        XCTAssertEqual(
            SendFailureEvidence.from(LFGError.transport(code: -1001, underlying: "timed out")),
            .transportFailed(urlErrorCode: -1001))
        XCTAssertEqual(
            SendFailureEvidence.from(URLError(.timedOut)),
            .transportFailed(urlErrorCode: -1001))
        XCTAssertEqual(SendFailureEvidence.from(LFGError.badURL), .unsendable)
    }

    /// End-to-end on the reported failure: a raw `URLError.timedOut` from a
    /// reachable host must come out `.confirming`, not `.terminal`.
    func testTimedOutURLErrorAgainstReachableHostIsConfirming() {
        XCTAssertEqual(classify(SendFailureEvidence.from(URLError(.timedOut))), .confirming)
        XCTAssertEqual(
            classify(SendFailureEvidence.from(URLError(.cannotFindHost))), .terminal)
    }

    /// A `notReachable` string with a host we believe is UP tells us nothing —
    /// it must not shortcut to terminal on the strength of its own name.
    func testNotReachableWithLiveHostConfirms() {
        XCTAssertEqual(
            classify(SendFailureEvidence.from(LFGError.notReachable(underlying: "lost"))),
            .confirming)
    }

    /// A request that cannot be built is terminal — there is nothing to confirm.
    func testUnsendableIsTerminal() {
        XCTAssertEqual(classify(.unsendable), .terminal)
        XCTAssertEqual(classify(.unsendable, hostStillDown: true), .requeue,
                       "except when the host is down: the drain will rebuild it")
    }
}

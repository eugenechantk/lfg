import Observation
import Testing
@testable import LFGCore

/// A change to one session must not wake views that only read another one.
@MainActor
struct KeyedObservationTests {
    private final class Flag: @unchecked Sendable {
        var fired = 0
    }

    private func track(_ body: () -> Void) -> Flag {
        let flag = Flag()
        withObservationTracking(body) { flag.fired += 1 }
        return flag
    }

    @Test func changeToAnotherKeyDoesNotNotify() {
        let observation = KeyedObservation<String>()
        let flag = track { observation.access("b") }
        observation.didChange("a")
        #expect(flag.fired == 0)
    }

    @Test func changeToTheReadKeyNotifies() {
        let observation = KeyedObservation<String>()
        let flag = track { observation.access("b") }
        observation.didChange("b")
        #expect(flag.fired == 1)
    }

    @Test func observerOfSeveralKeysHearsEachOfThem() {
        let observation = KeyedObservation<String>()
        let first = track { observation.access("a"); observation.access("b") }
        observation.didChange("b")
        #expect(first.fired == 1)

        // withObservationTracking is one-shot: re-arm, as SwiftUI does.
        let second = track { observation.access("a"); observation.access("b") }
        observation.didChange("a")
        #expect(second.fired == 1)
    }

    @Test func changeBeforeAnyReadIsHarmless() {
        let observation = KeyedObservation<String>()
        observation.didChange("never-read")
        let flag = track { observation.access("never-read") }
        observation.didChange("never-read")
        #expect(flag.fired == 1)
    }

    @Test func readOutsideTrackingRegistersNothing() {
        let observation = KeyedObservation<String>()
        observation.access("a")
        let flag = track { observation.access("b") }
        observation.didChange("a")
        #expect(flag.fired == 0)
    }
}

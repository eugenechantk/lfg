import Foundation
import Testing
@testable import LFGCore

@Suite("Desktop Sessions list (board dA2-sessions)")
struct DesktopSessionListTests {
    private let now = 1_800_000_000_000.0

    @Test("paused needs you; idle and closed are Recent")
    func groups() {
        #expect(DesktopSessionList.group(.needsInput) == .needsInput)
        #expect(DesktopSessionList.group(.paused) == .needsInput)
        #expect(DesktopSessionList.group(.working) == .working)
        #expect(DesktopSessionList.group(.idle) == .recent)
        #expect(DesktopSessionList.group(.closed) == .recent)
        #expect(DesktopListGroup.allCases.map(\.title) == ["Needs input", "Working", "Recent"])
    }

    @Test("the board's status lines: a question, a permission, working, closed, an offline host")
    func boardLines() {
        let q = DesktopSessionList.line(.init(state: .needsInput, question: "which launch page\ndirection first?",
                                               hostLabel: "Pro"))
        #expect(q == SessionRowLine(icon: .question, text: "Asks: which launch page direction first?", tone: .attention))

        let perm = DesktopSessionList.line(.init(state: .needsInput, question: "Do you want to proceed?",
                                                  promptKind: "permission",
                                                  permissionCommand: "launchctl kickstart -k gui/501/dev.omg.lfg",
                                                  hostLabel: "Pro"))
        #expect(perm.text == "Asks to run launchctl")

        #expect(DesktopSessionList.line(.init(state: .working, hostLabel: "Pro"))
                == SessionRowLine(icon: .liveDot, text: "Working", tone: .live))
        #expect(DesktopSessionList.line(.init(state: .closed, hostLabel: "Pro")).text == "Closed")
        #expect(DesktopSessionList.line(.init(state: .closed, hostLabel: "Air", hostOffline: true)).text == "Air is offline")
    }

    @Test("sign-in, plan, paused, idle and moving lines")
    func otherLines() {
        #expect(DesktopSessionList.line(.init(state: .needsInput, signInWebsite: "search.google.com", hostLabel: "Pro"))
                == SessionRowLine(icon: .signIn, text: "Sign in to search.google.com", tone: .attention))
        #expect(DesktopSessionList.line(.init(state: .needsInput, promptKind: "plan", hostLabel: "Pro")).text
                == "Asks to approve a plan")
        #expect(DesktopSessionList.line(.init(state: .needsInput, hostLabel: "Pro")).text == "Needs your input")
        #expect(DesktopSessionList.line(.init(state: .paused, pausedReason: "out_of_credits", hostLabel: "Pro")).text
                == "Paused · out of credits")
        #expect(DesktopSessionList.line(.init(state: .idle, hostLabel: "Pro")).text == "Ready for your next message")
        #expect(DesktopSessionList.line(.init(state: .working, hostLabel: "Pro", moving: true)).text == "Moving…")
    }

    @Test("the program a permission runs, past sudo, env assignments and paths")
    func program() {
        #expect(DesktopSessionList.program(in: "sudo /bin/launchctl kickstart -k x") == "launchctl")
        #expect(DesktopSessionList.program(in: "FOO=1 env bun test") == "bun")
        #expect(DesktopSessionList.program(in: "   ") == nil)
        #expect(DesktopSessionList.program(in: nil) == nil)
    }

    @Test("the time column reads like the board: 2m / 3h / 1d over 'ago', 'now' under a minute")
    func age() {
        #expect(DesktopSessionList.age(fromMs: now - 30_000, nowMs: now) == ("now", ""))
        #expect(DesktopSessionList.age(fromMs: now - 2 * 60_000, nowMs: now) == ("2m", "ago"))
        #expect(DesktopSessionList.age(fromMs: now - 3 * 3_600_000, nowMs: now) == ("3h", "ago"))
        #expect(DesktopSessionList.age(fromMs: now - 26 * 3_600_000, nowMs: now) == ("1d", "ago"))
        #expect(DesktopSessionList.age(fromMs: now - 15 * 86_400_000, nowMs: now) == ("2w", "ago"))
        #expect(DesktopSessionList.age(fromMs: now - 400 * 86_400_000, nowMs: now) == ("1y", "ago"))
        #expect(DesktopSessionList.age(fromMs: nil, nowMs: now) == ("", ""))
    }

    @Test("the board's meta lines")
    func meta() {
        #expect(DesktopSessionList.meta(project: "fiftystrong", host: "Pro", agent: "claude",
                                        model: "claude-opus-5-5", fromTask: false)
                == "fiftystrong · Pro · Claude Code opus")
        #expect(DesktopSessionList.meta(project: "lfg", host: "Pro", agent: "codex", model: "gpt-6.1", fromTask: false)
                == "lfg · Pro · Codex gpt-6.1")
        #expect(DesktopSessionList.meta(project: "lfg", host: "Air", agent: "codex", model: nil, fromTask: true)
                == "lfg · Air · Codex · from a task")
    }
}

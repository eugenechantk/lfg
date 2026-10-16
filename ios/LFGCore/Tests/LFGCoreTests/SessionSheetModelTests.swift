import Foundation
import Testing
@testable import LFGCore

@Suite("S2 session sheet: what the sheet shows")
struct SessionSheetModelTests {
    private let now = 1_800_000_000_000.0

    @Test("the board's session: subtitle, six tiles with badges, move to the other host, footer")
    func board() {
        var f = SessionSheetModel.Facts(sessionID: "7f3a9b2e-0000-4000-8000-000000000c21")
        f.hostLabel = "Pro"
        f.cwd = "/Users/eugene/dev/personal/lfg"
        f.startedAtMs = now - 2 * 3_600_000 - 5 * 60_000
        f.tmuxName = "lfg-fork-3"
        f.fileCount = 6
        f.subagentCount = 2
        f.otherHosts = ["Air"]
        let m = SessionSheetModel(f, nowMs: now)
        #expect(m.subtitle == "Pro · ~/dev/personal/lfg · started 2h ago")
        #expect(m.tiles.map(\.tile) == [.terminal, .files, .subagents, .signIn, .browserPreview, .iPhonePreview])
        #expect(m.tiles.map(\.badge) == [nil, 6, 2, nil, nil, nil])
        #expect(m.tiles.map(\.enabled) == [true, true, true, true, false, true])
        #expect(m.hostRow == .choose(current: "Pro"))
        #expect(m.footerTmux == "tmux lfg-fork-3")
        #expect(m.footerID == "id 7f3a…c21")
    }

    @Test("a session another frontend owns has no Terminal or Sign in tile")
    func externallyOwned() {
        var f = SessionSheetModel.Facts(sessionID: "abc")
        f.externallyOwned = true
        let m = SessionSheetModel(f, nowMs: now)
        #expect(m.tiles.map(\.tile) == [.files, .subagents, .browserPreview, .iPhonePreview])
        #expect(m.hostRow == nil)
        #expect(m.footerTmux == nil)
        #expect(m.footerID == "id abc")
    }

    @Test("tiles that can't act dim; waiting sign-ins show a count; an offline host dims Terminal")
    func availability() {
        var f = SessionSheetModel.Facts(sessionID: "s")
        f.waitingSignIns = 1
        f.hasBrowserFrame = true
        f.hostOffline = true
        let m = SessionSheetModel(f, nowMs: now)
        let byTile = Dictionary(uniqueKeysWithValues: m.tiles.map { ($0.tile, $0) })
        #expect(byTile[.terminal]?.enabled == false)
        #expect(byTile[.subagents]?.enabled == false)
        #expect(byTile[.files]?.enabled == true)
        #expect(byTile[.signIn]?.badge == 1)
        #expect(byTile[.browserPreview]?.enabled == true)
    }

    @Test("the host row opens a menu for one or several alternatives")
    func hostRow() {
        var f = SessionSheetModel.Facts(sessionID: "s")
        f.hostLabel = "Air"
        #expect(SessionSheetModel(f, nowMs: now).hostRow == .info(current: "Air"))
        f.otherHosts = ["Pro"]
        #expect(SessionSheetModel(f, nowMs: now).hostRow == .choose(current: "Air"))
        f.otherHosts = ["Pro", "Mini"]
        #expect(SessionSheetModel(f, nowMs: now).hostRow == .choose(current: "Air"))
    }

    @Test("effort labels match the board's segmented control")
    func effortLabels() {
        #expect(["low", "medium", "high", "max"].map(SessionSheetModel.effortLabel) == ["Low", "Med", "High", "Max"])
        #expect(SessionSheetModel.effortLabel("xhigh") == "X-High")
        #expect(SessionSheetModel.effortLabel("minimal") == "Min")
    }

    @Test("started ages: seconds, minutes, hours, days")
    func ages() {
        #expect(SessionSheetModel.age(fromMs: now - 40_000, toMs: now) == "40s")
        #expect(SessionSheetModel.age(fromMs: now - 5 * 60_000, toMs: now) == "5m")
        #expect(SessionSheetModel.age(fromMs: now - 3 * 86_400_000, toMs: now) == "3d")
    }
}

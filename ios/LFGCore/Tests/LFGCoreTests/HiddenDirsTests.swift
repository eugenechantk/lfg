import XCTest
@testable import LFGCore

final class HiddenDirsTests: XCTestCase {
    private let gbrain = "/Users/eugenechan/.gbrain"

    // MARK: The motivating case

    func testHidesExactDirectory() {
        XCTAssertTrue(HiddenDirs([gbrain]).hides(cwd: gbrain))
    }

    func testHidesDescendants() {
        let h = HiddenDirs([gbrain])
        XCTAssertTrue(h.hides(cwd: gbrain + "/vault"))
        XCTAssertTrue(h.hides(cwd: gbrain + "/vault/daily"))
    }

    func testDoesNotHideOtherDirectories() {
        let h = HiddenDirs([gbrain])
        XCTAssertFalse(h.hides(cwd: "/Users/eugenechan/dev/personal/lfg"))
        XCTAssertFalse(h.hides(cwd: "/Users/eugenechan"), "the PARENT is not hidden")
    }

    /// The whole reason matching is on segment boundaries: a plain `hasPrefix`
    /// would let `.gbrain` swallow a sibling that merely shares its prefix, and
    /// the user would lose real sessions without ever being told why.
    func testSiblingSharingAPrefixIsNotHidden() {
        let h = HiddenDirs([gbrain])
        XCTAssertFalse(h.hides(cwd: "/Users/eugenechan/.gbrainstorm"))
        XCTAssertFalse(h.hides(cwd: "/Users/eugenechan/.gbrain-old/x"))
    }

    // MARK: Inertness and unattributable sessions

    func testEmptyListHidesNothing() {
        XCTAssertFalse(HiddenDirs().hides(cwd: gbrain))
        XCTAssertTrue(HiddenDirs().isEmpty)
    }

    /// Hiding is an assertion about a directory; with no directory there is no
    /// assertion to make. A `cwd`-less session must stay visible rather than
    /// silently disappearing into whatever the first hidden entry happens to be.
    func testSessionWithoutCwdIsNeverHidden() {
        let h = HiddenDirs([gbrain])
        XCTAssertFalse(h.hides(cwd: nil))
        XCTAssertFalse(h.hides(cwd: ""))
        XCTAssertFalse(h.hides(cwd: "   "))
    }

    // MARK: Normalization

    func testTrailingAndRepeatedSlashesNormalize() {
        XCTAssertTrue(HiddenDirs([gbrain + "/"]).hides(cwd: gbrain))
        XCTAssertTrue(HiddenDirs([gbrain]).hides(cwd: gbrain + "/"))
        XCTAssertTrue(HiddenDirs(["/Users//eugenechan/.gbrain"]).hides(cwd: gbrain))
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertTrue(HiddenDirs(["  \(gbrain)  "]).hides(cwd: gbrain))
    }

    /// The hosts are macOS, where the filesystem is case-insensitive. A path typed
    /// with the wrong case matching nothing is a worse failure than over-matching.
    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(HiddenDirs(["/Users/Eugenechan/.GBrain"]).hides(cwd: gbrain))
    }

    /// This client cannot expand `~` against a *host's* home directory, so storing
    /// one would produce an entry that matches nothing and reads as a bug.
    func testTildeAndRelativePathsAreRejected() {
        XCTAssertTrue(HiddenDirs(["~/.gbrain"]).isEmpty)
        XCTAssertTrue(HiddenDirs([".gbrain"]).isEmpty)
        XCTAssertNil(HiddenDirs.normalize("~/.gbrain"))
    }

    /// Hiding `/` would empty the entire list with no obvious way back.
    func testRootIsRejected() {
        XCTAssertTrue(HiddenDirs(["/"]).isEmpty)
        XCTAssertTrue(HiddenDirs(["//"]).isEmpty)
        XCTAssertNil(HiddenDirs.normalize("/"))
    }

    // MARK: Mutation

    func testAddingIsIdempotentAcrossCaseAndTrailingSlash() {
        var h = HiddenDirs().adding(gbrain)
        h = h.adding(gbrain)
        h = h.adding(gbrain + "/")
        h = h.adding(gbrain.uppercased())
        XCTAssertEqual(h.paths, [gbrain])
    }

    func testAddingPreservesOrder() {
        let h = HiddenDirs().adding("/a/one").adding("/a/two").adding("/a/three")
        XCTAssertEqual(h.paths, ["/a/one", "/a/two", "/a/three"])
    }

    func testAddingAnInvalidPathIsANoOp() {
        XCTAssertEqual(HiddenDirs(["/a"]).adding("~/b").paths, ["/a"])
        XCTAssertEqual(HiddenDirs(["/a"]).adding("  ").paths, ["/a"])
    }

    func testRemoving() {
        let h = HiddenDirs(["/a", gbrain, "/b"])
        XCTAssertEqual(h.removing(gbrain).paths, ["/a", "/b"])
        XCTAssertEqual(h.removing(gbrain + "/").paths, ["/a", "/b"], "trailing slash still removes")
        XCTAssertEqual(h.removing("/nope").paths, ["/a", gbrain, "/b"])
    }

    func testRemovingRestoresVisibility() {
        let h = HiddenDirs([gbrain]).removing(gbrain)
        XCTAssertFalse(h.hides(cwd: gbrain))
    }

    func testDuplicateInputCollapses() {
        XCTAssertEqual(HiddenDirs([gbrain, gbrain + "/", gbrain.uppercased()]).paths, [gbrain])
    }

    func testMultipleEntriesAllApply() {
        let h = HiddenDirs([gbrain, "/private/tmp/cc-daemon-501"])
        XCTAssertTrue(h.hides(cwd: gbrain + "/vault"))
        XCTAssertTrue(h.hides(cwd: "/private/tmp/cc-daemon-501/96f10b56/spare"))
        XCTAssertFalse(h.hides(cwd: "/Users/eugenechan/dev/personal/lfg"))
    }

    // MARK: Patterns — the per-run temp directories autopilot actually produces

    /// The real motivating population: `gbrain` autopilot runs each session in
    /// `$TMPDIR/gbrain-claude-cli-cwd-<pid>`, so the path is different every run
    /// and a literal entry would have to be re-added forever.
    private let autopilot = "/private/var/folders/cd/_rd32xx17dv8ltmf4ctm5wn40000gn/T/gbrain-claude-cli-cwd-24267"

    func testPatternHidesEveryRunOfAPerRunDirectory() {
        let h = HiddenDirs(["*/gbrain-claude-cli-cwd-*"])
        XCTAssertTrue(h.hides(cwd: autopilot))
        XCTAssertTrue(h.hides(cwd: "/private/var/folders/cd/xxx/T/gbrain-claude-cli-cwd-99999"),
                      "a different pid AND a different TMPDIR must still match")
        XCTAssertFalse(h.hides(cwd: "/Users/eugenechan/dev/personal/lfg"))
    }

    func testPatternHidesChildrenOfWhatItMatches() {
        let h = HiddenDirs(["*/gbrain-claude-cli-cwd-*"])
        XCTAssertTrue(h.hides(cwd: autopilot + "/vault/notes"))
    }

    func testPatternDoesNotOverreachToAncestors() {
        let h = HiddenDirs(["*/gbrain-claude-cli-cwd-*"])
        XCTAssertFalse(h.hides(cwd: "/private/var/folders/cd/_rd32xx17dv8ltmf4ctm5wn40000gn/T"))
    }

    func testQuestionMarkMatchesExactlyOneCharacter() {
        XCTAssertTrue(HiddenDirs(["/a/b?"]).hides(cwd: "/a/bc"))
        XCTAssertFalse(HiddenDirs(["/a/b?"]).hides(cwd: "/a/bcd"))
        XCTAssertFalse(HiddenDirs(["/a/b?"]).hides(cwd: "/a/b"))
    }

    func testPatternsAreCaseInsensitive() {
        XCTAssertTrue(HiddenDirs(["*/GBRAIN-*"]).hides(cwd: autopilot))
    }

    func testLiteralEntriesAreNotTreatedAsPatterns() {
        XCTAssertFalse(HiddenDirs.isPattern("/Users/eugenechan/.gbrain"))
        XCTAssertTrue(HiddenDirs.isPattern("*/gbrain-*"))
    }

    /// A pattern of nothing but wildcards would empty the whole list with no
    /// visible explanation — the same footgun as hiding `/`.
    func testAllWildcardPatternsAreRejected() {
        XCTAssertTrue(HiddenDirs(["*"]).isEmpty)
        XCTAssertTrue(HiddenDirs(["**"]).isEmpty)
        XCTAssertTrue(HiddenDirs(["*/*"]).isEmpty)
        XCTAssertTrue(HiddenDirs(["?"]).isEmpty)
    }

    func testRelativePatternIsAcceptedButRelativeLiteralIsNot() {
        XCTAssertEqual(HiddenDirs(["*/gbrain-*"]).paths, ["*/gbrain-*"])
        XCTAssertTrue(HiddenDirs(["dev/personal"]).isEmpty)
        XCTAssertTrue(HiddenDirs(["~/*"]).isEmpty, "~ can't be expanded against a host's home")
    }

    // MARK: Glob primitive

    func testGlobBasics() {
        XCTAssertTrue(HiddenDirs.glob(pattern: "abc", matches: "abc"))
        XCTAssertFalse(HiddenDirs.glob(pattern: "abc", matches: "abd"))
        XCTAssertTrue(HiddenDirs.glob(pattern: "*", matches: ""))
        XCTAssertTrue(HiddenDirs.glob(pattern: "a*c", matches: "abbbc"))
        XCTAssertTrue(HiddenDirs.glob(pattern: "a*c*e", matches: "abcde"))
        XCTAssertFalse(HiddenDirs.glob(pattern: "a*c", matches: "ab"))
        XCTAssertTrue(HiddenDirs.glob(pattern: "*x*", matches: "aaaaax"))
        XCTAssertTrue(HiddenDirs.glob(pattern: "a**b", matches: "ab"), "consecutive stars collapse")
    }

    /// The classic backtracking trap: a greedy `*` must give characters back.
    func testGlobBacktracks() {
        XCTAssertTrue(HiddenDirs.glob(pattern: "*ab*cd", matches: "xxabxxcd"))
        XCTAssertTrue(HiddenDirs.glob(pattern: "*aab", matches: "aaab"))
        XCTAssertFalse(HiddenDirs.glob(pattern: "*aab", matches: "aaa"))
    }

    func testGlobStarCrossesPathSeparators() {
        XCTAssertTrue(HiddenDirs.glob(pattern: "/a/*/d", matches: "/a/b/c/d"))
    }

    // MARK: Suggested pattern

    func testSuggestsAPatternForPidSuffixedScratchDirectories() {
        XCTAssertEqual(HiddenDirs.suggestedPattern(for: autopilot), "*/gbrain-claude-cli-cwd-*")
        XCTAssertEqual(HiddenDirs.suggestedPattern(for: "/tmp/build.12345"), "*/build.*")
    }

    /// A wrong suggestion hides real work, so the heuristic stays narrow.
    func testNoSuggestionForStablePaths() {
        XCTAssertNil(HiddenDirs.suggestedPattern(for: gbrain))
        XCTAssertNil(HiddenDirs.suggestedPattern(for: "/Users/eugenechan/dev/personal/lfg"))
        XCTAssertNil(HiddenDirs.suggestedPattern(for: "/Users/e/project-v2"), "single trailing digit isn't a pid")
        XCTAssertNil(HiddenDirs.suggestedPattern(for: "/Users/e/ab-1234"), "too short a stem to generalize safely")
        XCTAssertNil(HiddenDirs.suggestedPattern(for: "*/already-*"))
    }

    /// The suggestion has to actually hide the directory it was suggested from —
    /// otherwise the swipe action silently does nothing.
    func testSuggestionHidesItsOwnSource() {
        let pattern = HiddenDirs.suggestedPattern(for: autopilot)!
        XCTAssertTrue(HiddenDirs([pattern]).hides(cwd: autopilot))
    }

    func testDisplayName() {
        XCTAssertEqual(HiddenDirs.displayName(for: gbrain), ".gbrain")
        XCTAssertEqual(HiddenDirs.displayName(for: "/Users/eugenechan/dev/personal/lfg"), "lfg")
    }
}

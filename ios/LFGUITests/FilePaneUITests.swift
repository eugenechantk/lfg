import XCTest

/// Exercises the shipping session UI against the local, sequenced host fixture.
@MainActor
final class FilePaneUITests: XCTestCase {
    func testHistoricalSourceRevealIsVisibleBelowHeader() async throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "LFG_SESSION_UI_FIXTURE": "1",
            "LFG_SESSION_UI_FIXTURE_PRO_URL": "http://127.0.0.1:18983",
            "LFG_SESSION_UI_FIXTURE_AIR_URL": "http://127.0.0.1:18984"
        ]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        print("FILE_PANE_RECORDING_READY")
        var recording = URLRequest(url: URL(string: "http://127.0.0.1:18983/fixture/recording-wait")!)
        recording.timeoutInterval = 180
        _ = try await URLSession.shared.data(for: recording)
        let session = app.staticTexts["sessionRow-pane-history"]
        if !session.waitForExistence(timeout: 3) {
            let idle = app.buttons["sessionGroupHeader-status-idle"]
            XCTAssertTrue(idle.waitForExistence(timeout: 10))
            idle.tap()
        }
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.tap()
        let source = app.buttons["inlineFileCard_source.md"]
        XCTAssertFalse(source.exists, "The original attachment starts outside the rendered window.")
        // iPad opens Files & links from the session sheet, as iPhone does.
        let options = app.buttons["sessionOptionsMenu"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["composerPill.files"].exists)
        options.tap()
        let files = app.buttons["sessionSheetTile-files"]
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        files.tap()
        let row = app.buttons["filePaneRow_source.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["filePaneMenu"].tap()
        app.buttons["filePaneReveal"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertTrue(source.isHittable)
        XCTAssertGreaterThan(source.frame.minY, 100, "The source must clear the overlaid header.")
        XCTAssertLessThan(source.frame.maxY, app.frame.height - 160)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Historical file source centered below the header"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testSplitPreviewTransitionsKeepComposerAlive() async throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "LFG_SESSION_UI_FIXTURE": "1",
            "LFG_SESSION_UI_FIXTURE_PRO_URL": "http://127.0.0.1:18983",
            "LFG_SESSION_UI_FIXTURE_AIR_URL": "http://127.0.0.1:18984"
        ]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        // The operator starts FlowDeck recording, then releases this handshake.
        print("FILE_PANE_RECORDING_READY")
        var recording = URLRequest(url: URL(string: "http://127.0.0.1:18983/fixture/recording-wait")!)
        recording.timeoutInterval = 180
        _ = try await URLSession.shared.data(for: recording)
        let report = app.buttons.matching(identifier: "inlineFileCard_report.md").firstMatch
        if !report.waitForExistence(timeout: 3) {
            let session = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fork session feature")).firstMatch
            if !session.waitForExistence(timeout: 2) {
                let idle = app.buttons["sessionGroupHeader-status-idle"]
                XCTAssertTrue(idle.waitForExistence(timeout: 10))
                idle.tap()
            }
            XCTAssertTrue(session.waitForExistence(timeout: 5))
            session.tap()
        }
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        // A previously remembered reader can be closed before starting the flow.
        let close = app.buttons["filePaneClose"]
        if close.exists { close.tap() }
        report.tap()
        let handle = app.buttons["filePaneResizeHandle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        if handle.value as? String == "420 points" { handle.tap() }
        XCTAssertEqual(handle.value as? String, "720 points")
        let composer = app.textFields["composer.message"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        if let existing = composer.value as? String, existing != "Message" {
            composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        composer.typeText("Draft stays live")
        app.buttons["filePaneExpand"].tap()
        let back = app.buttons["filePaneReturnToTranscript"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertEqual(composer.value as? String, "Draft stays live")
        app.buttons["filePaneAllFiles"].tap()
        let image = app.buttons["filePaneRow_before.png"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.tap()
        XCTAssertTrue(app.buttons["filePaneMedia_after.png"].waitForExistence(timeout: 5))
        app.buttons["filePaneMedia_after.png"].tap()
        app.buttons["filePaneExpand"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        close.tap()
        XCTAssertFalse(handle.exists)
        XCTAssertEqual(composer.value as? String, "Draft stays live")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Split preview closed with draft preserved"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPortraitReaderGoesFullScreenFromSheetAndSplit() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "LFG_SESSION_UI_FIXTURE": "1",
            "LFG_SESSION_UI_FIXTURE_PRO_URL": "http://127.0.0.1:18983",
            "LFG_SESSION_UI_FIXTURE_AIR_URL": "http://127.0.0.1:18984"
        ]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let image = app.buttons.matching(identifier: "inlineFileCard_after.png").firstMatch
        if !image.waitForExistence(timeout: 3) {
            let session = app.staticTexts["sessionRow-pane-primary"]
            if !session.waitForExistence(timeout: 3) {
                let idle = app.buttons["sessionGroupHeader-status-idle"]
                XCTAssertTrue(idle.waitForExistence(timeout: 10))
                idle.tap()
            }
            XCTAssertTrue(session.waitForExistence(timeout: 5))
            session.tap()
        }
        let close = app.buttons["filePaneClose"]
        if close.waitForExistence(timeout: 2) { close.tap() }
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.tap()

        // Sheet: split and full screen sit side by side.
        let dock = app.buttons["filePaneDock"]
        let expand = app.buttons["filePaneExpand"]
        let back = app.buttons["filePaneReturnToTranscript"]
        let reader = app.otherElements["filePaneReader"]
        // The split choice is remembered; start from the default sheet.
        let sheetButton = app.buttons["filePaneSheet"]
        if sheetButton.waitForExistence(timeout: 2) { sheetButton.tap() }
        XCTAssertTrue(dock.waitForExistence(timeout: 5))
        XCTAssertTrue(expand.exists)
        XCTAssertEqual(expand.label, "Full screen")
        let sheetFrame = reader.frame
        XCTAssertGreaterThan(sheetFrame.width, app.frame.width * 0.8, "The sheet uses most of the window's width.")

        expand.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(dock.exists)
        XCTAssertEqual(expand.label, "Exit full screen")
        XCTAssertGreaterThan(reader.frame.height, sheetFrame.height)
        XCTAssertGreaterThan(reader.frame.width, app.frame.width - 40)
        attach(app, "Portrait full screen from the sheet")

        expand.tap()
        XCTAssertTrue(dock.waitForExistence(timeout: 5), "Leaving full screen returns to the sheet.")
        dock.tap()
        XCTAssertTrue(sheetButton.waitForExistence(timeout: 5))
        XCTAssertEqual(expand.label, "Full screen")
        expand.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(sheetButton.waitForExistence(timeout: 5), "Leaving full screen returns to the split.")
        sheetButton.tap()
        XCTAssertTrue(dock.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertFalse(reader.waitForExistence(timeout: 2))
    }

    func testRotationKeepsTheOpenFile() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "LFG_SESSION_UI_FIXTURE": "1",
            "LFG_SESSION_UI_FIXTURE_PRO_URL": "http://127.0.0.1:18983",
            "LFG_SESSION_UI_FIXTURE_AIR_URL": "http://127.0.0.1:18984"
        ]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let image = app.buttons.matching(identifier: "inlineFileCard_after.png").firstMatch
        if !image.waitForExistence(timeout: 3) {
            let session = app.staticTexts["sessionRow-pane-primary"]
            if !session.waitForExistence(timeout: 3) {
                let idle = app.buttons["sessionGroupHeader-status-idle"]
                XCTAssertTrue(idle.waitForExistence(timeout: 10))
                idle.tap()
            }
            XCTAssertTrue(session.waitForExistence(timeout: 5))
            session.tap()
        }
        let close = app.buttons["filePaneClose"]
        if close.waitForExistence(timeout: 2) { close.tap() }
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.tap()
        let sheetButton = app.buttons["filePaneSheet"]
        if sheetButton.waitForExistence(timeout: 2) { sheetButton.tap() }
        XCTAssertTrue(app.buttons["filePaneDock"].waitForExistence(timeout: 5), "Starts in the portrait sheet.")

        // Sheet -> landscape: the file moves into the side pane.
        XCUIDevice.shared.orientation = .landscapeLeft
        let handle = app.buttons["filePaneResizeHandle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "Rotating keeps the file open, beside the transcript.")
        XCTAssertTrue(app.otherElements["filePaneReader"].exists)
        attach(app, "Rotated from the portrait sheet")

        // Side pane -> portrait: the file returns to the sheet.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["filePaneDock"].waitForExistence(timeout: 10), "Rotating back shows the file in the sheet.")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["filePaneDock"].waitForExistence(timeout: 10))
        app.buttons["filePaneClose"].tap()
        XCTAssertFalse(app.otherElements["filePaneReader"].waitForExistence(timeout: 2))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

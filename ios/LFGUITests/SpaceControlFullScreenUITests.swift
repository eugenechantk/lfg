import XCTest

@MainActor
final class SpaceControlFullScreenUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["LFG_CUA_UI_TESTS"] == "1" else {
            throw XCTSkip("Set LFG_CUA_UI_TESTS=1 to run tests that control the isolated Cua fixture.")
        }
        guard let baseURL = environment["LFG_CUA_BASE_URL"], !baseURL.isEmpty else {
            throw XCTSkip("Set LFG_CUA_BASE_URL to the isolated Cua fixture host.")
        }
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["LFG_SESSION_UI_FIXTURE"] = "1"
        app.launchEnvironment["LFG_SESSION_UI_FIXTURE_PRO_URL"] = baseURL
        app.launchEnvironment["LFG_SESSION_UI_FIXTURE_AIR_URL"] = baseURL
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testFullScreenControlFlow() throws {
        let liveSpace = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Live Space' OR identifier == 'Live Space'"))
            .firstMatch
        if !liveSpace.waitForExistence(timeout: 2) {
            let message = app.buttons["Message"]
            XCTAssertTrue(message.waitForExistence(timeout: 10))
            XCTAssertTrue(message.isHittable)
            message.tap()

            let space = app.descendants(matching: .any)
                .matching(identifier: "message_space_74d7beb8-d7fc-44f8-bc9c-d767ee24b8cb")
                .firstMatch
            XCTAssertTrue(space.waitForExistence(timeout: 15))
            XCTAssertTrue(waitUntil { space.isHittable })
            space.tap()
            if !liveSpace.waitForExistence(timeout: 5), space.exists, space.isHittable {
                space.tap()
            }
        }
        XCTAssertTrue(liveSpace.waitForExistence(timeout: 15))
        liveSpace.tap()

        let takeControl = app.buttons["message_live_take_control"]
        XCTAssertTrue(takeControl.waitForExistence(timeout: 20))
        takeControl.tap()

        let done = app.buttons["message_control_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        let screen = app.descendants(matching: .any)
            .matching(identifier: "message_control_screen").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 20))
        XCTAssertTrue(waitUntil { screen.frame.height > screen.frame.width })
        capture("01-control-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil { screen.frame.width > screen.frame.height })
        capture("02-control-landscape-left")

        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(waitUntil { screen.frame.width > screen.frame.height })
        capture("03-control-landscape-right")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil { screen.frame.height > screen.frame.width })

        screen.pinch(withScale: 2.0, velocity: 1.0)
        XCTAssertTrue(waitUntil { self.zoomPercent(screen) > 100 })
        capture("04-control-zoomed")

        // XCTest's public API has no two-finger drag. The test-only helper
        // submits two simultaneous XCTest touch paths through the runner.
        let frame = screen.frame
        var panError: NSError?
        let panned = LFGPerformTwoFingerPan(
            CGPoint(x: frame.midX - 35, y: frame.midY - 20),
            CGPoint(x: frame.midX - 105, y: frame.midY - 20),
            CGPoint(x: frame.midX + 35, y: frame.midY + 20),
            CGPoint(x: frame.midX - 35, y: frame.midY + 20),
            0.8,
            &panError
        )
        XCTAssertTrue(panned, panError?.localizedDescription ?? "Two-finger pan synthesis failed")
        sleep(2)
        capture("05-after-two-finger-pan")

        // Keep the viewport zoomed and manually panned, then send a one-finger
        // guest drag. The fixture counters and pointer prove transformed input.
        let transformedStart = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55))
        let transformedEnd = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55))
        transformedStart.press(forDuration: 0.3, thenDragTo: transformedEnd)
        sleep(2)
        capture("05b-after-panned-zoomed-guest-drag")

        app.buttons["message_control_fit"].tap()
        XCTAssertTrue(waitUntil { self.zoomPercent(screen) == 100 })
        capture("06-after-fit")

        let rightClickPoint = guestPoint(in: screen, x: 0.35, y: 0.87)
        var rightClickError: NSError?
        let rightClicked = LFGPerformTwoFingerTap(rightClickPoint, 8, &rightClickError)
        XCTAssertTrue(rightClicked, rightClickError?.localizedDescription ?? "Two-finger tap synthesis failed")
        sleep(2)
        capture("07-after-two-finger-tap")

        // At 2x, the visible center remains guest coordinate 0.5,0.5. A
        // one-finger drag across the central viewport exercises transformed
        // guest coordinates without invoking the two-finger viewport pan.
        screen.pinch(withScale: 2.0, velocity: 1.0)
        XCTAssertTrue(waitUntil { self.zoomPercent(screen) > 100 })
        let dragStart = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let dragEnd = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        dragStart.press(forDuration: 0.3, thenDragTo: dragEnd)
        sleep(2)
        capture("08-after-zoomed-guest-drag")

        app.buttons["message_control_fit"].tap()
        XCTAssertTrue(waitUntil { self.zoomPercent(screen) == 100 })
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil { screen.frame.width > screen.frame.height })
        guestCoordinate(in: screen, x: 0.23, y: 0.44).tap()
        app.buttons["message_control_keyboard"].tap()
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 3) { continueButton.tap() }
        app.typeText("FS  Test")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        app.typeText("C\nD")
        sleep(3)
        capture("09-landscape-keyboard-input")

        app.buttons["message_control_keyboard"].tap()
        app.buttons["message_control_done"].tap()
        XCTAssertTrue(app.buttons["message_live_take_control"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil { self.app.frame.height > self.app.frame.width })
        capture("10-after-done")
    }

    private func guestPoint(in element: XCUIElement, x: CGFloat, y: CGFloat) -> CGPoint {
        let frame = element.frame
        let aspect: CGFloat = 1.6
        let width = min(frame.width, frame.height * aspect)
        let height = width / aspect
        return CGPoint(
            x: frame.minX + (frame.width - width) / 2 + x * width,
            y: frame.minY + (frame.height - height) / 2 + y * height
        )
    }

    private func guestCoordinate(in element: XCUIElement, x: CGFloat, y: CGFloat) -> XCUICoordinate {
        let frame = element.frame
        let point = guestPoint(in: element, x: x, y: y)
        return element.coordinate(withNormalizedOffset: CGVector(
            dx: (point.x - frame.minX) / frame.width,
            dy: (point.y - frame.minY) / frame.height
        ))
    }

    private func zoomPercent(_ element: XCUIElement) -> Int {
        let text = String(describing: element.value ?? "")
        return Int(text.split(whereSeparator: { !$0.isNumber }).first ?? "0") ?? 0
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return condition()
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["LFG_UI_EVIDENCE_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(name).appendingPathExtension("png")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? screenshot.pngRepresentation.write(to: url, options: .atomic)
    }
}

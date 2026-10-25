import XCTest

@MainActor
final class ProgressiveImagePreviewUITests: XCTestCase {
    func testOriginalReplacesPreviewWithoutMovingViewportAndSupportsDeepPinch() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "LFG_FILE_SHARE_FIXTURE": "1",
            "LFG_FILE_SHARE_FIXTURE_URL": "/fixture/canvas.png",
            "LFG_FILE_SHARE_FIXTURE_HOST": "http://127.0.0.1:8879",
            "LFG_FILE_SHARE_FIXTURE_LABEL": "Canvas",
            "LFG_FILE_SHARE_FIXTURE_NEXT": "/fixture/next.pdf"
        ]
        app.launch()
        let image = app.images["filePreviewImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        XCTAssertEqual(image.value as? String, "Preview, 727 by 2400 pixels")
        // The SwiftUI wrapper flattens the native scroll container out of AX.
        // Pinching the app centers both fingers inside the image viewport.
        let fitWidth = app.frame.width
        XCTAssertGreaterThan(fitWidth, 300)
        app.pinch(withScale: 2.5, velocity: 2)
        let previewFrame = image.frame
        XCTAssertGreaterThan(previewFrame.width, fitWidth * 1.5)
        let fullResolution = NSPredicate(format: "value == %@", "Full resolution, 4784 by 15784 pixels")
        let ready = XCTNSPredicateExpectation(predicate: fullResolution, object: image)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        let originalFrame = image.frame
        XCTAssertEqual(originalFrame.width, previewFrame.width, accuracy: 1)
        XCTAssertEqual(originalFrame.minX, previewFrame.minX, accuracy: 1)
        XCTAssertEqual(originalFrame.minY, previewFrame.minY, accuracy: 1)
        app.pinch(withScale: 3, velocity: 2)
        let detailFrame = image.frame
        print("IMAGE_PREVIEW_GEOMETRY fitWidth=\(fitWidth) preview=\(previewFrame) original=\(originalFrame) detail=\(detailFrame)")
        XCTAssertGreaterThan(detailFrame.width, fitWidth * 4.1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Original canvas at source detail"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

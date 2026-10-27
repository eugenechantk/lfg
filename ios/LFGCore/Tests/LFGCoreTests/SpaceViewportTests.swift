import Foundation
import Testing
@testable import LFGCore

struct SpaceViewportTests {
    @Test func portraitAndLandscapeFit() {
        #expect(SpaceViewport.fittedSize(in: CGSize(width: 400, height: 800), aspect: 1.6) == CGSize(width: 400, height: 250))
        #expect(SpaceViewport.fittedSize(in: CGSize(width: 800, height: 400), aspect: 1.6) == CGSize(width: 640, height: 400))
    }
    @Test func normalizedCoordinatesIgnoreDisplayScale() {
        let size = CGSize(width: 640, height: 400)
        #expect(SpaceViewport.normalized(CGPoint(x: 160, y: 300), in: size) == CGPoint(x: 0.25, y: 0.75))
        // Gesture locations are converted into the zoomed content view's local
        // bounds by UIKit, so zoom and content offsets cannot enter this mapping.
        #expect(SpaceViewport.normalized(CGPoint(x: 320, y: 200), in: size) == CGPoint(x: 0.5, y: 0.5))
    }
    @Test func invalidGeometryAndOutsidePointsAreBounded() {
        #expect(SpaceViewport.fittedSize(in: .zero, aspect: .nan) == .zero)
        #expect(SpaceViewport.normalized(CGPoint(x: -100, y: 800), in: CGSize(width: 640, height: 400)) == CGPoint(x: 0, y: 1))
        #expect(SpaceViewport.normalized(.zero, in: .zero) == .zero)
    }
}

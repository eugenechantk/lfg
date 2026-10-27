import Foundation

/// Layout and input use the same unscaled content bounds. UIKit converts
/// touches through the scroll view's zoom transform before normalizing them.
public enum SpaceViewport {
    public static func fittedSize(in viewport: CGSize, aspect: CGFloat) -> CGSize {
        guard viewport.width > 0, viewport.height > 0, aspect.isFinite, aspect > 0 else { return .zero }
        let width = min(viewport.width, viewport.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }
    public static func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / max(1, size.width))),
                y: min(1, max(0, point.y / max(1, size.height))))
    }
}

public enum BrowserPreviewDockEdge: Sendable, Equatable {
    case leading
    case trailing
}

public struct BrowserPreviewPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Platform-neutral placement rules for the floating browser preview.
/// SwiftUI owns gesture state; this type keeps clamping and edge intent
/// deterministic and directly testable.
public struct BrowserPreviewLayout: Sendable, Equatable {
    public let containerWidth: Double
    public let containerHeight: Double
    public let previewWidth: Double
    public let previewHeight: Double
    public let margin: Double
    public let dockingOvershoot: Double

    public init(
        containerWidth: Double,
        containerHeight: Double,
        previewWidth: Double,
        previewHeight: Double,
        margin: Double = 10,
        dockingOvershoot: Double = 24
    ) {
        self.containerWidth = containerWidth
        self.containerHeight = containerHeight
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.margin = margin
        self.dockingOvershoot = dockingOvershoot
    }

    public var leadingCenterX: Double {
        min(containerWidth / 2, margin + previewWidth / 2)
    }

    public var trailingCenterX: Double {
        max(leadingCenterX, containerWidth - margin - previewWidth / 2)
    }

    public func constrained(_ point: BrowserPreviewPoint) -> BrowserPreviewPoint {
        let top = min(containerHeight / 2, margin + previewHeight / 2)
        let bottom = max(top, containerHeight - margin - previewHeight / 2)
        return BrowserPreviewPoint(
            x: min(max(point.x, leadingCenterX), trailingCenterX),
            y: min(max(point.y, top), bottom)
        )
    }

    /// Dock only when a drag pushes beyond the normal resting boundary. A card
    /// resting flush to an edge must remain draggable instead of docking on tap.
    public func dockEdge(forUnconstrainedX x: Double) -> BrowserPreviewDockEdge? {
        if x <= leadingCenterX - dockingOvershoot { return .leading }
        if x >= trailingCenterX + dockingOvershoot { return .trailing }
        return nil
    }
}

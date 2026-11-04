import Foundation

/// Geometry and snap policy, independent of a particular window or UI framework.
public enum FilePaneLayout {
    public enum Presentation: Equatable, Sendable { case side, top, sheet }
    public enum HorizontalSnap: Equatable, Sendable { case close, width(Double), full }
    public enum PortraitSnap: Equatable, Sendable { case close, fraction(Double), sheet }

    public static func presentation(width: Double, height: Double, isPad: Bool, portraitDocked: Bool) -> Presentation {
        guard isPad, width >= 600 else { return .sheet }
        if width > height, width >= 840 { return .side }
        return portraitDocked ? .top : .sheet
    }

    public static func keepsSidebar(windowWidth: Double, sidebarWidth: Double) -> Bool {
        windowWidth - sidebarWidth >= 1_016 // 400 transcript + 600 preview + handle
    }

    public static func horizontalSnap(proposed: Double) -> HorizontalSnap {
        if proposed < 320 { return .close }
        if proposed > 820 { return .full }
        return .width(proposed < 570 ? 420 : 720)
    }

    public static func portraitSnap(fraction: Double) -> PortraitSnap {
        if fraction < 0.18 { return .close }
        if fraction > 0.86 { return .sheet }
        return .fraction([0.4, 0.55, 0.7].min(by: { abs($0 - fraction) < abs($1 - fraction) }) ?? 0.55)
    }

    /// The reader sits in the window, not in a sheet. Full screen always fills the window.
    public static func isInline(isOpen: Bool, presentation: Presentation, fullWidth: Bool) -> Bool {
        isOpen && (presentation != .sheet || fullWidth)
    }

    public enum HeaderControl: Equatable, Sendable { case dock, sheet, expand, collapse }

    /// The layout buttons before •••. Every layout can go full screen; landscape calls it full width.
    public static func headerControls(inSheet: Bool, fullWidth: Bool, isPortrait: Bool, canDock: Bool) -> [HeaderControl] {
        if inSheet { return (canDock ? [.dock] : []) + [.expand] }
        if fullWidth { return [.collapse] }
        return (isPortrait ? [.sheet] : []) + [.expand]
    }
}

/// The zoom an image shows before any pinch.
public enum ImageFit {
    public static func restingScale(boundsWidth: Double, boundsHeight: Double,
                                    imageWidth: Double, imageHeight: Double, fitsWhole: Bool) -> Double {
        let width = boundsWidth / imageWidth
        return fitsWhole ? min(width, boundsHeight / imageHeight) : width
    }
}

/// A session's remembered reader choice. New arrivals only affect the index.
public struct FilePaneState: Codable, Equatable, Sendable {
    public var isOpen = false
    public var selection: MediaRef?
    public var showingFiles = false
    public var fullWidth = false
    public var portraitDocked = false
    public var portraitFraction = 0.55
    public private(set) var widths: [String: Double] = [:]
    public private(set) var unseen: Set<String> = []
    public private(set) var newFiles: Set<String> = []
    private var known: Set<String>?
    private var newestResourceTimestamp: Double?

    public init() {}

    private var category: String {
        selection.map { $0.kind.rawValue } ?? "index"
    }

    public var width: Double {
        widths[showingFiles ? "index" : category] ??
            ((!showingFiles && (selection?.kind == .image || selection?.kind == .video)) ? 420 : 720)
    }

    public mutating func setWidth(_ width: Double) {
        widths[showingFiles ? "index" : category] = width
    }

    public mutating func open(_ ref: MediaRef) {
        selection = ref
        isOpen = true
        showingFiles = false
        unseen.remove(ref.id)
        newFiles.remove(ref.id)
    }

    public mutating func showFiles() {
        showingFiles = true
        isOpen = true
        unseen.removeAll()
    }

    public mutating func close() {
        isOpen = false
        fullWidth = false
    }

    public mutating func observe(_ resources: TranscriptResources) {
        let ids = Set(resources.files.map(\.id) + resources.links.map(\.id))
        if let known {
            let earliestArrival = newestResourceTimestamp ?? -.infinity
            let freshFiles = resources.files.filter {
                !known.contains($0.id) && ($0.ts ?? .infinity) >= earliestArrival
            }.map(\.id)
            let freshLinks = resources.links.filter {
                !known.contains($0.id) && ($0.ts ?? .infinity) >= earliestArrival
            }.map(\.id)
            unseen.formUnion(freshFiles + freshLinks)
            newFiles.formUnion(freshFiles + freshLinks)
        }
        if let latest = (resources.files.compactMap(\.ts) + resources.links.compactMap(\.ts)).max() {
            newestResourceTimestamp = max(newestResourceTimestamp ?? latest, latest)
        }
        known = ids
        unseen.formIntersection(ids)
        newFiles.formIntersection(ids)
    }
}

public enum FilePaneRevision {
    /// Client-side rewrite evidence. Reads and failed tool calls never refresh a file.
    public static func token(for path: String, messages: [SessionMessage]) -> String {
        let failures = Set(messages.filter { $0.kind == "tool_result" && $0.isError == true }.compactMap(\.toolUseId))
        for message in messages.reversed() {
            if message.kind == "text", MediaScanner.scan(message.text, includeInlineImages: true).contains(where: { $0.raw == path }) {
                return "mention:\(message.stableID):\(message.text.hashValue)"
            }
            guard message.kind == "tool_use", let tool = message.tool,
                  ["write", "edit", "multiedit", "apply_patch"].contains(tool.name.lowercased()),
                  !failures.contains(message.toolUseId ?? ""),
                  tool.target == path || MediaScanner.scan(tool.target ?? "", includeInlineImages: true).contains(where: { $0.raw == path }) else { continue }
            return "rewrite:\(message.stableID):\(message.text.hashValue)"
        }
        return ""
    }
}

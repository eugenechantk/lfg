import Foundation

// The reading column for wide screens (iPad, LFG UI Map canvas page "iPad (Oct 17)",
// boards `ip-session`, `ip-session-full`, `ip-new`, `ip-task`). Content that reads
// as prose — the transcript, the composer and its strips, a task's detail — sits in
// one centered column so a line never runs past about 80 characters. Pure widths,
// so the rule is tested here and the views only apply it.
//
// It keys off the width the content is offered, never the device: a phone
// screen (402pt) is below the cap and lays out exactly as before.
public enum ReadableColumn {
    /// The column's widest extent, its 16pt side padding included (688pt of text).
    public static let maxWidth: CGFloat = 720

    /// A column at least this wide lets a user bubble grow past the phone's cap.
    /// iPad portrait beside the list offers 494pt and keeps the phone bubble.
    public static let wideBubbleColumn: CGFloat = 600

    /// The phone's user bubble text cap (board `s2-view`).
    public static let compactBubbleText: CGFloat = 290

    /// The user bubble text cap inside a wide column (board `ip-session`).
    public static let wideBubbleText: CGFloat = 480

    /// The column width for a content area `container` points wide.
    public static func width(in container: CGFloat) -> CGFloat {
        guard container.isFinite, container > 0 else { return maxWidth }
        return min(container, maxWidth)
    }

    /// How far the column sits in from each side of `container`.
    public static func sideInset(in container: CGFloat) -> CGFloat {
        guard container.isFinite, container > maxWidth else { return 0 }
        return (container - maxWidth) / 2
    }

    /// The most text a user bubble may hold in a column `columnWidth` wide.
    public static func userBubbleTextCap(columnWidth: CGFloat) -> CGFloat {
        columnWidth >= wideBubbleColumn ? wideBubbleText : compactBubbleText
    }
}

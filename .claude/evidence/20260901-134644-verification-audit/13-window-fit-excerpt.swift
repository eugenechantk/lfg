    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.dropFirst().first == "--attach-command" else { return }
        let rest = Array(args.dropFirst(2))
        guard rest.count == 2 || rest.count == 3 else {
            print("usage: lfg --attach-command <ssh-target> <tmux-session> [automatic|ssh|mosh-bridged]")
            Darwin.exit(1)
        }
        let transport = rest.count == 3 ? RemoteTransport(rawValue: rest[2]) : .automatic
        guard let transport else {
            print("unknown transport \(rest[2]); expected automatic, ssh, or mosh-bridged")
            Darwin.exit(1)
        }
        let moshPath: String?
        switch transport {
        case .automatic: moshPath = Opener.mosh
        case .ssh: moshPath = nil
        case .moshBridged: moshPath = Opener.moshBridged
        }
        print(Opener.remoteAttachCommand(sshTarget: rest[0], tmuxName: rest[1], moshPath: moshPath))
        fflush(stdout)
        Darwin.exit(0)
    }
}

/// Off-screen window harness: proves the main window actually accepts a narrow
/// size and that its toolbar still fits every item there (no » overflow).
/// Runs without a visible screen, so it works over ssh / on a locked login.
enum WindowFitCLI {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.dropFirst().first == "--window-fit" else { return }
        let widths = args.dropFirst(2).compactMap { Double($0) }.map { CGFloat($0) }
        guard !widths.isEmpty else {
            print("{\"ok\":false,\"error\":\"usage: lfg --window-fit <width> [width…]\"}")
            Darwin.exit(1)
        }
        let window = makeWindow()
        settle(0.6)

        var rows: [String] = []
        var ok = true
        for width in widths {
            window.setContentSize(NSSize(width: width, height: 700))
            settle(0.5)
            // The compact toolbar is driven by a SwiftUI state change one
            // layout pass behind the resize; nudge and settle again so the
            // measurement reads the toolbar the user ends up looking at.
            window.setContentSize(NSSize(width: width + 1, height: 700))
            settle(0.3)
            window.setContentSize(NSSize(width: width, height: 700))
            settle(0.5)
            let actual = window.contentLayoutRect.width
            let items = window.toolbar?.items.count ?? -1
            let visible = window.toolbar?.visibleItems?.count ?? -1
            // -1 means AppKit never surfaced the toolbar to us; treat that as a
            // failed measurement rather than a silent pass.
            let fits = items > 0 && visible == items
            let honored = abs(actual - width) < 2
            if !fits || !honored { ok = false }
            let visibleIds = Set((window.toolbar?.visibleItems ?? []).map(\.itemIdentifier.rawValue))
            let dropped = (window.toolbar?.items ?? []).enumerated()
                .filter { !visibleIds.contains($0.element.itemIdentifier.rawValue) }
                .map { "\"#\($0.offset) w=\(Int(($0.element.view?.frame.width ?? -1).rounded()))\"" }
                .joined(separator: ",")
            let shown = (window.toolbar?.visibleItems ?? []).enumerated()
                .map { "\"#\($0.offset) w=\(Int(($0.element.view?.frame.width ?? -1).rounded()))\"" }
                .joined(separator: ",")
            rows.append("""
            {"requested":\(Int(width)),"contentWidth":\(Int(actual.rounded())),\
            "toolbarItems":\(items),"visibleToolbarItems":\(visible),\
            "shown":[\(shown)],"dropped":[\(dropped)],"fits":\(fits),"widthHonored":\(honored)}
            """)
        }
        window.orderOut(nil)
        print("{\"ok\":\(ok),\"widths\":[\(rows.joined(separator: ","))]}")
        fflush(stdout)
        Darwin.exit(ok ? 0 : 1)
    }

    /// Renders the real window — toolbar chrome included — at a given width,
    /// without Screen Recording permission or a woken display, by asking the
    /// window's frame view to draw itself into a bitmap.
    @MainActor
    static func runShotIfRequested() {
        let args = CommandLine.arguments
        guard args.dropFirst().first == "--window-shot" else { return }
        guard args.count >= 4, let width = Double(args[2]) else {
            print("{\"ok\":false,\"error\":\"usage: lfg --window-shot <width> <output.png> [--search]\"}")
            Darwin.exit(1)
        }
        let output = URL(fileURLWithPath: args[3])
        let window = makeWindow(sessions: true, compactSearchShown: args.contains("--search"))
        window.setContentSize(NSSize(width: CGFloat(width), height: 560))
        settle(1.2)
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            print("{\"ok\":false,\"error\":\"no frame view to draw\"}")
            Darwin.exit(1)
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("{\"ok\":false,\"error\":\"could not encode png\"}")
            Darwin.exit(1)
        }

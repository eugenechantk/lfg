import LFGCore
import SwiftUI
import UIKit

/// What a tile or row asks the session view to do once the sheet is gone.
/// Anything that presents something else (a sheet, the terminal, an alert)
/// has to wait for this sheet to finish dismissing first.
enum SessionSheetAction {
    case rename, terminal, files, subagents, signIn, browserPreview, iPhonePreview, confirmEnd, markedUnread
}

/// S2 session sheet (board `s2-menu`). It replaces the old ••• menu: the tiles
/// open the session's tools, the first card changes the session (model,
/// effort, host, fork, unread), the second stops or ends it, and the footer
/// copies the tmux name and the session id.
struct SessionSheet: View {
    let session: Session
    let sid: String
    let isBusy: Bool
    let subagentCount: Int
    let waitingSignIns: Int
    let messages: [SessionMessage]
    let onAction: (SessionSheetAction) -> Void

    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var resourceCount = 0
    @State private var checkingMove = false
    @State private var staleMove: StaleMove?

    struct StaleMove: Identifiable {
        let target: Host
        let behindSeconds: TimeInterval
        var id: String { target.id }
    }

    /// Board `s2-menu`: the sheet's top edge sits 732pt above the screen's bottom.
    static let height: CGFloat = 732

    private var externallyOwned: Bool { session.isExternallyOwned }

    private var model: SessionSheetModel {
        var f = SessionSheetModel.Facts(sessionID: sid)
        f.externallyOwned = externallyOwned
        f.hostLabel = store.host(forSession: sid)?.label
        f.cwd = session.cwd
        f.startedAtMs = session.startedAt
        f.tmuxName = session.tmuxName ?? session.tmuxTarget
        f.fileCount = fileCount
        f.subagentCount = subagentCount
        f.waitingSignIns = waitingSignIns
        f.hasBrowserFrame = store.browserFrames[sid] != nil
        f.hostOffline = store.isOffline(sid)
        f.otherHosts = transferTargets.map(\.label)
        return SessionSheetModel(f, nowMs: Date().timeIntervalSince1970 * 1_000)
    }

    private var fileCount: Int {
        #if DEBUG
        if let n = store.s2FixtureFiles(sid) { return n }
        #endif
        return resourceCount
    }

    var body: some View {
        let m = model
        VStack(alignment: .leading, spacing: 0) {
            // Board: the header sits 20pt from the left, but its close button
            // 16pt from the right (in line with the cards).
            header(m)
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.top, 20)
                // Board: the tile grid sits 96pt below the sheet's top whatever the
                // subtitle does (a wrapped one eats into the gap), never closer than
                // 10pt to the header.
                .frame(minHeight: 96 - 10, alignment: .top)
            VStack(spacing: 14) {
                tileGrid(m)
                settingsCard(m)
                lifecycleCard
                footer(m)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(S2.surface)
        .presentationCornerRadius(38)
        .task(id: messages.count) {
            let snapshot = messages
            let resources = await Task.detached { TranscriptResourceIndex.collect(from: snapshot) }.value
            resourceCount = resources.files.count + resources.links.count
        }
        .confirmationDialog(
            "Move anyway?",
            isPresented: Binding(get: { staleMove != nil }, set: { if !$0 { staleMove = nil } }),
            titleVisibility: .visible,
            presenting: staleMove
        ) { move in
            Button("Move to \(move.target.label)") { startMove(to: move.target, preflight: .ready) }
            Button("Cancel", role: .cancel) {}
        } message: { move in
            let source = store.host(forSession: sid)?.label ?? "the current host"
            Text("\(move.target.label)'s copy of this conversation is \(SessionTransfer.behindLabel(move.behindSeconds)) behind \(source). Moving now continues from that older copy; the newer turns stay only on \(source).")
        }
    }

    // MARK: Header

    private func header(_ m: SessionSheetModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Button { finish(.rename) } label: {
                    Text(session.title.isEmpty ? "Session" : session.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(S2.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .cssLineBox(size: 22, lineHeight: 28)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit the session title")
                .accessibilityIdentifier("sessionSheetTitle")
                .frame(height: 44)
                if !m.subtitle.isEmpty {
                    Text(m.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(S2.secondaryInk)
                        // Wraps, as on the board, when a long host name needs it.
                        .fixedSize(horizontal: false, vertical: true)
                        // CSS `line-height: normal` for 14px is 16pt; SF's own line is 16.7.
                        .padding(.vertical, -0.35)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SheetCloseButton { dismiss() }
            .accessibilityIdentifier("sessionSheetClose")
        }
    }

    // MARK: Tiles

    private func tileGrid(_ m: SessionSheetModel) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(m.tiles, id: \.tile) { state in
                Button { open(state.tile) } label: { tile(state) }
                    .buttonStyle(.plain)
                    .disabled(!state.enabled)
                    .accessibilityIdentifier("sessionSheetTile-\(state.tile.rawValue)")
            }
        }
    }

    private func tile(_ state: SessionSheetModel.TileState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetGlyph(kind: .tile(state.tile))
                .stroke(Self.blue, style: StrokeStyle(lineWidth: 1.8 * 22 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
            Spacer(minLength: 0)
            Text(state.tile.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(S2.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .cssLineBox(size: 14, lineHeight: 17)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 9, trailing: 10))
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let badge = state.badge {
                Text("\(badge)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(S2.ink)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Self.chromeFill))
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(S2.chip))
        .opacity(state.enabled ? 1 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func open(_ tile: SessionSheetModel.Tile) {
        switch tile {
        case .terminal: finish(.terminal)
        case .files: finish(.files)
        case .subagents: finish(.subagents)
        case .signIn: finish(.signIn)
        case .browserPreview: finish(.browserPreview)
        case .iPhonePreview: finish(.iPhonePreview)
        }
    }

    // MARK: Settings card

    @ViewBuilder
    private func settingsCard(_ m: SessionSheetModel) -> some View {
        let rows = settingsRows(m)
        if !rows.isEmpty {
            card(rows)
        }
    }

    private func settingsRows(_ m: SessionSheetModel) -> [AnyView] {
        var rows: [AnyView] = []
        if !externallyOwned { rows.append(AnyView(modelRow)) }
        if let levels = effortLevels { rows.append(AnyView(effortRow(levels))) }
        if let host = m.hostRow { rows.append(AnyView(hostRow(host))) }
        if canFork { rows.append(AnyView(forkRow)) }
        if ManualUnread.canMarkUnread(sid) { rows.append(AnyView(unreadRow)) }
        return rows
    }

    private var modelRow: some View {
        let switching = store.switchingModelSessionIds.contains(sid)
        let sections = SessionHandoff.modelSections(
            current: AgentKind(rawValue: session.agent) ?? .claude,
            closed: session.closed,
            catalog: store.modelCatalog(forSession: sid)
        )
        return Menu {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.models, id: \.self) { name in
                        Button {
                            Task {
                                if let id = await store.switchModel(sid, to: AgentModelSelection(agent: section.agent, model: name)) {
                                    store.requestSelection(id)
                                }
                            }
                        } label: {
                            if session.agent == section.agent.rawValue && session.model == name {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                        .disabled(switching || sid.hasPrefix("local-"))
                    }
                }
            }
        } label: {
            row(height: 42) {
                Text(switching ? "Switching model…" : "Model")
                    .font(.system(size: 17))
                    .foregroundStyle(S2.white)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                AgentMark(agent: session.agent)
                Text(session.model.map(ModelChipLabel.model) ?? "Default")
                    .font(.system(size: 17))
                    .foregroundStyle(S2.secondaryInk)
                    .lineLimit(1)
                    .layoutPriority(1)
                chevron
            }
        }
        .menuOrder(.fixed)
        .accessibilityIdentifier("sessionSheetModel")
    }

    /// Effort levels for this live session's model; nil hides the row (closed
    /// or externally owned sessions, models without effort control).
    private var effortLevels: [String]? {
        guard !externallyOwned, !session.closed, let kind = AgentKind(rawValue: session.agent) else { return nil }
        #if DEBUG
        if sid.hasPrefix("s2fx-") { return ["low", "medium", "high", "max"] }
        #endif
        let levels = store.modelCatalog(forSession: sid).efforts(for: kind, model: session.model)
        return levels.isEmpty ? nil : levels
    }

    private func effortRow(_ levels: [String]) -> some View {
        let changing = store.changingEffortSessionIds.contains(sid)
            || store.switchingModelSessionIds.contains(sid) || sid.hasPrefix("local-")
        #if DEBUG
        let current = sid.hasPrefix("s2fx-") ? (session.effort ?? "high") : session.effort
        #else
        let current = session.effort
        #endif
        return row(height: 48) {
            Text("Effort")
                .font(.system(size: 17))
                .foregroundStyle(S2.white)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            // Effort names follow the CLIs ("Medium"), as on the model chip; a
            // model with more levels than fit falls back to the short names.
            ViewThatFits(in: .horizontal) {
                effortControl(levels, current: current, changing: changing, label: SessionEffort.displayName)
                effortControl(levels, current: current, changing: changing, label: SessionSheetModel.effortLabel)
            }
            .layoutPriority(1)
        }
    }

    private func effortControl(_ levels: [String], current: String?, changing: Bool,
                               label: @escaping (String) -> String) -> some View {
        HStack(spacing: 0) {
            ForEach(levels, id: \.self) { level in
                Button {
                    Task { await store.setEffort(sid, to: level) }
                } label: {
                    Text(label(level))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(S2.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .frame(minWidth: 49, minHeight: 28)
                        .background {
                            if level == current {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Self.segmentSelected)
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(changing)
                .accessibilityIdentifier("sessionSheetEffort-\(level)")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Self.chromeFill))
        .opacity(changing ? 0.5 : 1)
        .fixedSize()
    }

    @ViewBuilder
    private func hostRow(_ host: SessionSheetModel.HostRow) -> some View {
        switch host {
        case .choose(let current):
            Menu {
                Label(current, systemImage: "checkmark")
                ForEach(transferTargets, id: \.id) { t in
                    Button(t.label) { requestMove(to: t) }
                        .accessibilityIdentifier("sessionSheetHostOption-\(t.id)")
                }
            } label: {
                hostLabel(value: checkingMove ? "Checking…" : current, showsChevron: true)
            }
            .menuOrder(.fixed)
            .disabled(checkingMove)
            .accessibilityIdentifier("sessionSheetHost")
        case .info(let current):
            hostLabel(value: current, showsChevron: false)
        }
    }

    private func hostLabel(value: String, showsChevron: Bool) -> some View {
        // As the board's CSS lays it out: a value that fits sits at the right;
        // a long one wraps, starting 10pt after "Host", and the row grows.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                hostTitle.frame(maxWidth: .infinity, alignment: .leading)
                hostValue(value).lineLimit(1).fixedSize()
                if showsChevron { chevron }
            }
            HStack(spacing: 10) {
                hostTitle
                hostValue(value)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron { chevron }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
    }

    private var hostTitle: some View {
        Text("Host")
            .font(.system(size: 17))
            .foregroundStyle(S2.white)
            .fixedSize()
    }

    private func hostValue(_ value: String) -> Text {
        Text(value)
            .font(.system(size: 17))
            .foregroundStyle(S2.secondaryInk)
    }

    private var forkRow: some View {
        Button {
            let request = ForkRequest(sessionId: sid)
            dismiss()
            Task { @MainActor in
                if let newID = await store.fork(request) { store.requestSelection(newID) }
            }
        } label: {
            row(height: 42) {
                SheetGlyph(kind: .fork)
                    .stroke(Self.blue, style: StrokeStyle(lineWidth: 2 * 18 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
                Text(externallyOwned ? "Continue in LFG" : "Fork session")
                    .font(.system(size: 17))
                    .foregroundStyle(Self.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isForking(sid))
        .accessibilityIdentifier("sessionSheetFork")
    }

    private var unreadRow: some View {
        let unread = store.isManuallyUnread(sid)
        return Button {
            if unread {
                store.markRead(sid)
                dismiss()
            } else {
                store.markUnread(sid)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                finish(.markedUnread)
            }
        } label: {
            row(height: 42) {
                Circle()
                    .fill(Self.unreadDot)
                    .frame(width: 9, height: 9)
                    .frame(width: 18)
                Text(unread ? "Mark as read" : "Mark as unread")
                    .font(.system(size: 17))
                    .foregroundStyle(Self.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sessionSheetUnread")
    }

    // MARK: Lifecycle card

    @ViewBuilder
    private var lifecycleCard: some View {
        let rows = lifecycleRows
        if !rows.isEmpty { card(rows) }
    }

    private var lifecycleRows: [AnyView] {
        var rows: [AnyView] = []
        if isBusy && !externallyOwned {
            rows.append(AnyView(
                Button {
                    Task { await store.interrupt(sid) }
                    dismiss()
                } label: {
                    row(height: 42) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Self.stopInk)
                            .frame(width: 11, height: 11)
                            .frame(width: 18)
                        Text("Stop current turn")
                            .font(.system(size: 17))
                            .foregroundStyle(S2.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sessionSheetStop")
            ))
        }
        if !externallyOwned {
            rows.append(AnyView(
                Button { finish(.confirmEnd) } label: {
                    row(height: 42) {
                        SheetGlyph(kind: .endCircle)
                            .stroke(S2.failed, style: StrokeStyle(lineWidth: 2 * 18 / 24, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                        Text("End session")
                            .font(.system(size: 17))
                            .foregroundStyle(S2.failed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sessionSheetEnd")
            ))
        }
        return rows
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ m: SessionSheetModel) -> some View {
        if m.footerTmux != nil || m.footerID != nil {
            HStack(spacing: 0) {
                if let tmux = m.footerTmux, let name = session.tmuxName ?? session.tmuxTarget {
                    Button(tmux) { copy(name) }
                        .accessibilityIdentifier("sessionSheetCopyTmux")
                    Text(" · ")
                }
                if let id = m.footerID {
                    Button(id) { copy(sid) }
                        .accessibilityIdentifier("sessionSheetCopyID")
                    Text(" · tap to copy")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(S2.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pieces

    private func card(_ rows: [AnyView]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                rows[i]
                if i < rows.count - 1 {
                    // Board: `border-bottom: 0.5px solid #38383A`.
                    Rectangle().fill(S2.surfaceBorder).frame(height: 0.5)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(S2.chip))
    }

    private func row<Content: View>(height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 16)
            .frame(height: height)
            .contentShape(Rectangle())
    }

    private var chevron: some View {
        BoardGlyph(kind: .chevronRight, lineWidth: 3)
            .foregroundStyle(Self.chevronInk)
            .frame(width: 11, height: 11)
    }

    private func finish(_ action: SessionSheetAction) {
        onAction(action)
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Moving hosts

    private var transferTargets: [Host] {
        guard !sid.isEmpty, !session.closed, let current = store.host(forSession: sid)?.id else { return [] }
        return settings.hosts.filter { $0.id != current }
    }

    private var canFork: Bool {
        !sid.isEmpty && (session.agent == "claude" || session.agent == "codex")
    }

    /// Ask the target first; the source is untouched until it says go. A copy
    /// that is behind asks before moving, as the old menu did.
    private func requestMove(to target: Host) {
        guard !checkingMove else { return }
        checkingMove = true
        Task { @MainActor in
            let check = await store.transferPreflight(sid, to: target)
            checkingMove = false
            if case .behind(let seconds) = check {
                staleMove = StaleMove(target: target, behindSeconds: seconds)
                return
            }
            startMove(to: target, preflight: check)
        }
    }

    private func startMove(to target: Host, preflight: SessionTransfer.Preflight) {
        dismiss()
        Task { @MainActor in _ = await store.transfer(sid, to: target, preflight: preflight) }
    }

    // MARK: Colours (board `s2-menu`)

    static let blue = S2.color(dark: 0x409CFF, light: 0x007AFF)
    static let chromeFill = S2.color(dark: 0x3A3A3C, light: 0xE5E5EA)
    static let chromeInk = S2.color(dark: 0xD1D1D6, light: 0x3A3A3C)
    static let chevronInk = S2.color(dark: 0x48484A, light: 0xC7C7CC)
    static let segmentSelected = S2.color(dark: 0x636366, light: 0xFFFFFF)
    static let unreadDot = S2.color(dark: 0xBF5AF0, light: 0xAF52DE)
    static let stopInk = S2.color(dark: 0xF2F2F8, light: 0x1C1C1E)
}

/// The agent's mark beside the model name: Claude's clay "C" (board `s2-menu`),
/// Codex's own logo tile.
private struct AgentMark: View {
    let agent: String

    var body: some View {
        if agent.contains("codex") {
            Image("agent-codex")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Text("C")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(red: 0xB5 / 255, green: 0x56 / 255, blue: 0x2F / 255)))
        }
    }
}

/// The sheet's icons, drawn from the board's SVGs (24-unit box).
struct SheetGlyph: Shape {
    enum Kind {
        case tile(SessionSheetModel.Tile)
        case pencil, close, fork, endCircle
    }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: rect.minX + (x - r) * k, y: rect.minY + (y - r) * k, width: 2 * r * k, height: 2 * r * k))
        }
        var path = Path()
        func line(_ points: [(CGFloat, CGFloat)], close: Bool = false) {
            guard let first = points.first else { return }
            path.move(to: p(first.0, first.1))
            for pt in points.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
            if close { path.closeSubpath() }
        }
        switch kind {
        case .tile(.terminal):
            line([(4, 5), (20, 5), (20, 19), (4, 19)], close: true)
            line([(8, 10), (11, 12), (8, 14)])
            line([(13, 15), (16, 15)])
        case .tile(.files):
            line([(6, 2.5), (14, 2.5), (18.5, 7), (18.5, 21.5), (6, 21.5)], close: true)
            line([(14, 2.5), (14, 7), (18.5, 7)])
            line([(9, 12), (15, 12)])
            line([(9, 16), (15, 16)])
        case .tile(.subagents):
            line([(6, 7.2), (6, 16.8)])
            path.move(to: p(8, 6.2))
            path.addCurve(to: p(16, 12), control1: p(13, 7), control2: p(16, 9))
            path.addPath(circle(6, 5, 2))
            path.addPath(circle(6, 19, 2))
            path.addPath(circle(18, 12, 2))
        case .tile(.signIn):
            path.addPath(circle(8, 15, 4))
            line([(11, 12), (20, 3)])
            line([(16, 7), (19, 10)])
        case .tile(.browserPreview):
            line([(3, 4), (21, 4), (21, 18), (3, 18)], close: true)
            line([(3, 8), (21, 8)])
            line([(6, 6), (6.01, 6)])
            line([(8.5, 6), (8.51, 6)])
        case .tile(.iPhonePreview):
            line([(7, 2.5), (17, 2.5), (17, 21.5), (7, 21.5)], close: true)
            line([(11, 18.5), (13, 18.5)])
        case .pencil:
            line([(4, 20), (8, 20), (19, 9), (15, 5), (4, 16)], close: true)
        case .close:
            line([(6, 6), (18, 18)])
            line([(18, 6), (6, 18)])
        case .fork:
            path.addPath(circle(6, 5, 2.2))
            path.addPath(circle(18, 5, 2.2))
            path.addPath(circle(12, 19, 2.2))
            path.move(to: p(6, 7.2))
            path.addCurve(to: p(12, 16.8), control1: p(6, 11.2), control2: p(12, 11.2))
            path.move(to: p(18, 7.2))
            path.addCurve(to: p(12, 16.8), control1: p(18, 11.2), control2: p(12, 11.2))
        case .endCircle:
            path.addPath(circle(12, 12, 9))
            line([(9, 9), (15, 15)])
            line([(15, 9), (9, 15)])
        }
        return path
    }
}

import LFGCore
import SwiftUI

// MARK: - Sheet scaffold (native presentation)

/// Chrome shared by the three pickers.
///
/// These are presented with SwiftUI's own `.sheet` rather than a hand-rolled
/// overlay, so translucency, the grabber, the drag-to-dismiss and the corner
/// treatment all come from the system. The design draws the panel inset 6pt from
/// the sides and bottom, which a system sheet cannot do — Eugene's call is to
/// follow Apple's sheets, so that inset is a deliberate, known deviation.
struct SheetScaffold<Content: View>: View {
    let title: String
    /// Commits the live selection and dismisses.
    let onConfirm: () -> Void
    /// Reverts to the selection the sheet opened with, then dismisses.
    let onCancel: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, onClose: onCancel, onConfirm: onConfirm)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(.regularMaterial)
    }
}

// MARK: - C7 SheetHeader

/// 70pt header: grabber, 44x44 circular ✕, centred title, 44x44 blue ✓.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // No custom grabber: `.presentationDragIndicator(.visible)` draws the
            // system one, and two grabbers would stack.
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NewSessionPalette.sheetTitle)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .accessibilityIdentifier("sheet.title")

            HStack {
                circleButton(system: "xmark",
                             fill: NewSessionPalette.closeButtonFill,
                             tint: NewSessionPalette.sheetTitle,
                             label: "Cancel",
                             id: "sheet.close",
                             glyphSize: 10,
                             action: onClose)
                Spacer()
                circleButton(system: "checkmark",
                             fill: NewSessionPalette.confirmButtonFill,
                             tint: .white,
                             label: "Done",
                             id: "sheet.confirm",
                             glyphSize: 11,
                             action: onConfirm)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
        }
        .frame(height: 70)
    }

    private func circleButton(system: String, fill: Color, tint: Color,
                              label: String, id: String, glyphSize: CGFloat,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Glyph sized from the design's DRAWN path, not its 24-unit SVG box.
            Image(systemName: system)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - C6 SheetSearchField

struct SheetSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(NewSessionPalette.labelSecondary)

            TextField("", text: $text,
                      prompt: Text(placeholder).foregroundStyle(NewSessionPalette.placeholder))
                .font(.system(size: 17))
                .foregroundStyle(NewSessionPalette.labelPrimary)
                .tint(NewSessionPalette.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(NewSessionPalette.searchFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityIdentifier("sheet.search")
    }
}

/// Shared scrolling body. `ScrollView` + `LazyVStack`, never `List` — an opaque
/// `List` row background seams against the translucent panel.
private struct SheetList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) { content }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - S2 Directory sheet

struct DirectorySheet: View {
    let recents: [DirectoryEntry]
    let all: [DirectoryEntry]
    let selectedPath: String
    let onSelect: (DirectoryEntry) -> Void
    let onAddByPath: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var query = ""

    private func match(_ entries: [DirectoryEntry]) -> [DirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
    }

    var body: some View {
        SheetScaffold(title: "Directory", onConfirm: onConfirm, onCancel: onCancel) {
            VStack(spacing: 0) {
                SheetSearchField(placeholder: "Search directories", text: $query)

                SheetList {
                    let recentMatches = match(recents)
                    if !recentMatches.isEmpty {
                        SectionHeader(title: "Recent")
                        ForEach(recentMatches) { row($0) }
                    }

                    let allMatches = match(all)
                    if !allMatches.isEmpty {
                        SectionHeader(title: "All directories")
                        ForEach(allMatches) { row($0) }
                    }

                    // Not drawn in the design, but the shipping menu offered it and
                    // dropping it would remove a capability. Kept at the end, with
                    // no leading separator (the design draws separators above rows
                    // only, and this would read as a trailing rule).
                    Button(action: onAddByPath) {
                        HStack(spacing: 12) {
                            Color.clear.frame(width: 18, height: 18)
                            Text("Add directory by path…")
                                .font(.system(size: 17))
                                .foregroundStyle(NewSessionPalette.accent)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sheet.row.addByPath")
                }
            }
        }
    }

    private func row(_ entry: DirectoryEntry) -> some View {
        VStack(spacing: 0) {
            RowSeparator()
            Button { onSelect(entry) } label: {
                HStack(spacing: 12) {
                    SelectionCheck(selected: entry.path == selectedPath)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.system(size: 17))
                            .foregroundStyle(NewSessionPalette.labelPrimary)
                        Text(entry.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(NewSessionPalette.labelTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet.row.\(entry.name)")
        }
    }
}

/// One directory offered by the picker.
struct DirectoryEntry: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
}

// MARK: - S3 Host sheet

struct HostSheet: View {
    let hosts: [Host]
    let reachability: [String: Reachability]
    let selectedHostID: String?
    let onSelect: (Host) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // No search field — the design's host sheet has none, which is also why it
        // is the shortest of the three panels.
        SheetScaffold(title: "Host", onConfirm: onConfirm, onCancel: onCancel) {
            SheetList {
                ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                    if index > 0 { RowSeparator() }
                    row(host)
                }
            }
        }
    }

    private func isReachable(_ host: Host) -> Bool { reachability[host.id] == .ok }

    private func subtitle(_ host: Host) -> (String, Color) {
        guard isReachable(host) else { return ("Unreachable", NewSessionPalette.statusWarn) }
        return (host.isDefault ? "Reachable · Default" : "Reachable", NewSessionPalette.labelTertiary)
    }

    private func row(_ host: Host) -> some View {
        let (text, tint) = subtitle(host)
        return Button { onSelect(host) } label: {
            HStack(spacing: 12) {
                SelectionCheck(selected: host.id == selectedHostID)
                Circle()
                    .fill(isReachable(host) ? NewSessionPalette.statusOK : NewSessionPalette.statusWarn)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.label)
                        .font(.system(size: 17))
                        .foregroundStyle(NewSessionPalette.labelPrimary)
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sheet.row.\(host.label)")
    }
}

/// One row of the model picker. Identified by runtime + model so the same model
/// name appearing under two runtimes stays two distinct rows.
private struct ModelChoice: Identifiable {
    let kind: AgentKind
    let name: String
    var id: String { "\(kind.rawValue)/\(name)" }
}

// MARK: - S4 Model sheet

struct ModelSheet: View {
    let selectedAgent: AgentKind
    let selectedModel: String
    /// Selecting a model sets the agent too — this is the whole reason the
    /// standalone agent picker was removed from the screen.
    let onSelect: (AgentKind, String) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var query = ""

    private func models(for kind: AgentKind) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return kind.models }
        return kind.models.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        SheetScaffold(title: "Model", onConfirm: onConfirm, onCancel: onCancel) {
            VStack(spacing: 0) {
                SheetSearchField(placeholder: "Search models", text: $query)

                SheetList {
                    // Every runtime is listed, not just the three the design's
                    // sample data happened to show — dropping the ai-sdk kinds
                    // would make them unreachable now the agent pill is gone.
                    ForEach(AgentKind.allCases) { kind in
                        let rows = models(for: kind)
                        if !rows.isEmpty {
                            SectionHeader(title: kind.displayName, topPadding: 11, bottomPadding: 6)
                            // Identity must be runtime+model, not the model name:
                            // `claude-opus-5` exists under BOTH `aisdk` and `claude`,
                            // and a duplicate ForEach id makes SwiftUI silently drop
                            // the second group's rows — they keep their layout space
                            // but draw nothing and expose no a11y elements.
                            ForEach(rows.map { ModelChoice(kind: kind, name: $0) }) { choice in
                                row(kind: choice.kind, model: choice.name)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(kind: AgentKind, model: String) -> some View {
        Button { onSelect(kind, model) } label: {
            HStack(spacing: 12) {
                SelectionCheck(selected: kind == selectedAgent && model == selectedModel)
                Text(model)
                    .font(.system(size: 17))
                    .foregroundStyle(NewSessionPalette.labelPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sheet.row.\(model)")
    }
}

import SwiftUI
#if canImport(LFGCore)
import LFGCore
#endif

private struct UsagePalette {
    let dark: Bool
    let desktop: Bool
    private func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
    var sheet: Color { color(dark ? (desktop ? 0x232327 : 0x1C1C1E) : (desktop ? 0xFFFFFF : 0xF2F2F7)) }
    var card: Color { color(dark ? (desktop ? 0x26262B : 0x2C2C2E) : (desktop ? 0xEFEFEF : 0xFFFFFF)) }
    var ink: Color { color(dark ? 0xF4F4F6 : 0x1C1C1E) }
    var secondary: Color { color(dark ? 0xA1A1A6 : 0x6C6C70) }
    var meta: Color { color(dark ? 0x8E8E93 : 0x6C6C70) }
    var accent: Color { color(dark ? (desktop ? 0x8FB8FF : 0x409CFF) : 0x0071E3) }
    var fill: Color { color(dark ? (desktop ? 0x3B8EFF : 0x0A6EE0) : (desktop ? 0x007AFF : 0x0088FF)) }
    var warning: Color { color(dark ? (desktop ? 0xFFB340 : 0xFF9F0A) : 0xB35100) }
    var danger: Color { color(dark ? (desktop ? 0xFF6B61 : 0xFF453A) : 0xD70015) }
    var separator: Color { (dark ? Color.white : Color.black).opacity(0.08) }
    var track: Color { (dark ? Color.white : Color.black).opacity(0.16) }
    var control: Color { dark ? Color.white.opacity(desktop ? 0.07 : 0.10) : desktop ? color(0xE9E9E9) : Color.black.opacity(0.08) }
    func tone(_ tone: AccountUsageTone) -> Color {
        switch tone {
        case .normal: fill
        case .high, .critical: warning
        case .exhausted: danger
        case .unknown: secondary
        }
    }
}

/// Shared native content. Its owner supplies host transport and presentation.
struct AccountUsageContent: View {
    let store: AccountUsageStore
    var desktop = false
    var close: (() -> Void)?
    var measured: ((CGFloat) -> Void)?
    let refresh: () async -> Void
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    private func usageFont(phone: CGFloat, mac: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: desktop ? mac : phone * textScale, weight: weight)
    }
    private var palette: UsagePalette { UsagePalette(dark: scheme == .dark, desktop: desktop) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        if store.cards.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                if store.refreshing { ProgressView().accessibilityIdentifier("usage_loading") }
                                Text(store.refreshing ? "Reading usage limits…" : "No accounts to show")
                                    .font(usageFont(phone: 17, mac: 13, weight: .semibold))
                                if !store.refreshing { Text("Add a host in Settings to see its account limits.").font(.subheadline).foregroundStyle(palette.secondary) }
                            }
                            .padding(.vertical, 24)
                            .accessibilityIdentifier("usage_empty")
                        }
                        ForEach(store.cards) { card in
                            accountCard(card, now: context.date)
                        }
                        Text("Quotas belong to the account, not to one session.")
                            .font(usageFont(phone: 12, mac: 10))
                            .foregroundStyle(palette.meta)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, desktop ? 12 : 16)
                            .accessibilityIdentifier("usage_scope_note")
                    }
                    .padding(.horizontal, desktop ? 14 : 20)
                    .padding(.bottom, desktop ? 14 : 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured?($0 + (desktop ? 42 : 48)) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("usage_scroll")
        }
        .foregroundStyle(palette.ink)
        .background(palette.sheet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("usage_sheet")
    }

    private var header: some View {
        ZStack {
            if !desktop { Text("Usage limits").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.ink) }
            HStack {
                if desktop {
                    Text("Usage limits").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                } else {
                    Button("Close") { close?() }
                        .font(.system(size: 17))
                        .frame(minWidth: 64, minHeight: 44, alignment: .leading)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("usage_dismiss")
                }
                Spacer(minLength: 100)
                Button { Task { await refresh() } } label: {
                    if desktop {
                        Group {
                            if store.refreshing { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
                        }
                        .frame(width: 24, height: 24)
                        .background(palette.track.opacity(0.5), in: Circle())
                    } else {
                        HStack(spacing: 5) {
                            if store.refreshing { ProgressView().controlSize(.mini) }
                            Text(store.refreshing ? "Refreshing" : "Refresh")
                        }
                        .font(.system(size: 17))
                        .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                    }
                }
                .disabled(store.refreshing)
                .accessibilityLabel("Refresh usage limits")
                .accessibilityIdentifier("usage_refresh")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .tint(palette.accent)
        .foregroundStyle(palette.accent)
        .padding(.horizontal, desktop ? 14 : 16)
        .frame(height: desktop ? 42 : 48)
        .overlay(alignment: .bottom) { if desktop { palette.separator.frame(height: 0.5) } }
    }

    private func accountCard(_ card: AccountUsageCard, now: Date) -> some View {
        VStack(alignment: .leading, spacing: desktop ? 5 : 8) {
            Text(card.reading.providerName.uppercased())
                .font(usageFont(phone: 13, mac: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.meta)
                .padding(.top, desktop ? 14 : 22)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.reading.plan ?? "Plan not reported")
                        .font(usageFont(phone: 17, mac: 13, weight: .semibold))
                    Text(card.identityLine)
                        .font(usageFont(phone: 13, mac: 11))
                        .foregroundStyle(palette.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, desktop ? 12 : 16)
                .padding(.vertical, desktop ? 9 : 13)

                if card.failed {
                    notice(title: card.offline ? "\(card.hostNames) \(card.hosts.count > 1 ? "are" : "is") offline" : "Couldn’t update limits from \(card.hostNames)",
                           body: AccountUsagePresentation.failureBody(card.reading, now: now),
                           error: true, retry: true)
                } else if card.reading.status == "api" {
                    notice(title: "API billing", body: "This sign-in pays per token. There is no subscription quota to show.")
                } else if card.reading.status == "unavailable" {
                    notice(title: "No reading yet", body: "Usage limits aren’t available from \(card.hostNames) yet.")
                }

                if card.reading.status != "api" && card.reading.status != "unavailable" {
                    ForEach(card.reading.windows) { window in
                        quotaRow(window, provider: card.reading.providerName, now: now)
                    }
                }
                if card.reading.accountId == nil, card.reading.fetchedAt != nil {
                    Text("This host didn’t identify its account, so it is shown on its own. It may share an account with another host.")
                        .font(usageFont(phone: 13, mac: 11))
                        .foregroundStyle(palette.secondary)
                        .padding(desktop ? 10 : 14)
                        .overlay(alignment: .top) { palette.separator.frame(height: 0.5) }
                }
                let stale = AccountUsagePresentation.stale(card.reading.fetchedAt, now: now)
                Text(footer(card, stale: stale, now: now))
                    .font(usageFont(phone: 12, mac: 10))
                    .foregroundStyle(card.failed || stale ? palette.warning : palette.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, desktop ? 12 : 16)
                    .padding(.vertical, desktop ? 7 : 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { palette.separator.frame(height: 0.5) }
            }
            .background(palette.card, in: RoundedRectangle(cornerRadius: desktop ? 12 : 20))
            .opacity(card.offline ? 0.58 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("usage_card_\(card.reading.provider)_\(card.id)")
        }
    }

    private func quotaRow(_ window: AccountQuotaWindow, provider: String, now: Date) -> some View {
        let row = AccountUsagePresentation.row(window, now: now)
        return VStack(alignment: .leading, spacing: desktop ? 6 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .fontWeight(.regular)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(row.value).fontWeight(.semibold).monospacedDigit().foregroundStyle(palette.tone(row.tone))
            }
            .font(usageFont(phone: 16, mac: 12))
            if let percent = row.percent {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.tone(row.tone)).frame(width: geometry.size.width * percent / 100)
                    }
                }
                .frame(height: desktop ? 5 : 6)
                .accessibilityHidden(true)
            }
            Text(row.subtitle)
                .font(usageFont(phone: 13, mac: 11))
                .foregroundStyle(row.tone == .critical || row.tone == .exhausted ? palette.tone(row.tone) : palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, desktop ? 12 : 16)
        .padding(.vertical, desktop ? 9 : 13)
        .overlay(alignment: .top) { palette.separator.frame(height: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider), \(row.title), \(row.percent == nil ? row.value : row.value + " used"), \(row.subtitle)")
        .accessibilityIdentifier("usage_row_\(window.id)")
    }

    private func notice(title: String, body: String, error: Bool = false, retry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(usageFont(phone: 16, mac: 12, weight: .semibold)).foregroundStyle(error ? palette.danger : palette.ink)
            Text(body).font(usageFont(phone: 13, mac: 11)).foregroundStyle(palette.secondary)
            if retry {
                Button { Task { await refresh() } } label: {
                    Text("Try again")
                        .font(usageFont(phone: 16, mac: 12, weight: .semibold))
                        .padding(.horizontal, desktop ? 10 : 14)
                        .frame(minHeight: desktop ? 24 : 34)
                        .background(palette.control, in: Capsule())
                        .frame(minHeight: desktop ? 24 : 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .disabled(store.refreshing)
                .accessibilityIdentifier("usage_retry")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(desktop ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((error ? palette.danger : palette.meta).opacity(error ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: desktop ? 8 : 12))
        .overlay {
            if error {
                RoundedRectangle(cornerRadius: desktop ? 8 : 12)
                    .strokeBorder(palette.danger.opacity(desktop ? 0.28 : 0.30), lineWidth: 1)
            }
        }
        .padding(.horizontal, desktop ? 12 : 16)
        .padding(.bottom, desktop ? 9 : 13)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(error ? "usage_error" : "usage_unavailable")
    }

    private func footer(_ card: AccountUsageCard, stale: Bool, now: Date) -> String {
        if store.refreshing { return "Refreshing…" }
        var text = AccountUsagePresentation.age(card.reading.fetchedAt, now: now)
        if card.offline { text = "\(card.hostNames) offline · \(text.lowercased())" }
        else if stale { text += " · may be out of date" }
        else if card.hosts.count > 1 { text += " · Shared across \(card.hostNames)" }
        else { text += " · \(card.hostNames)" }
        return text
    }
}

#if os(iOS)
struct AccountUsageSheet: View {
    let store: AccountUsageStore
    let refresh: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 700
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var body: some View {
        AccountUsageContent(store: store, close: { dismiss() }, measured: { contentHeight = $0 }, refresh: refresh)
            .frame(width: isPad ? 460 : nil, height: isPad ? min(754, max(340, contentHeight)) : nil)
            .presentationSizing(.fitted)
            .presentationDetents(isPad ? [.large] : [.height(min(740, max(340, contentHeight))), .large])
            .presentationDragIndicator(isPad ? .hidden : .visible)
            .presentationCornerRadius(isPad ? 20 : 34)
            .task { await refresh() }
    }
}
#endif

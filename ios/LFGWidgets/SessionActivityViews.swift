import SwiftUI

enum SessionActivityState: String {
    case working
    case blocked
    case finished

    var statusText: String {
        switch self {
        case .working: "Working"
        case .blocked: "Needs input"
        case .finished: "Finished"
        }
    }

    var tint: Color {
        switch self {
        case .working: .lfgStateWorking
        case .blocked: .lfgStateNeedsInput
        case .finished: .lfgLabelSecondary
        }
    }

    var accessibilityName: String { rawValue }
}

struct SessionStateGlyph: View {
    let state: SessionActivityState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(state == .blocked ? Color.lfgGlyphAlertTile : Color.lfgGlyphAppFill)
                .frame(width: 16, height: 16)

            if state == .blocked {
                Image(systemName: "asterisk")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.lfgGlyphAlertStroke)
            } else {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.lfgGlyphAppDot)
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityIdentifier("la.glyph.\(state.accessibilityName)")
    }
}

struct StatusLabel: View {
    let state: SessionActivityState

    var body: some View {
        Text(state.statusText)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(state.tint)
            .lineLimit(1)
    }
}

struct DirectoryTag: View {
    let dir: String

    var body: some View {
        if !dir.isEmpty {
            Text("· \(dir)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.lfgLabelQuaternary)
                .lineLimit(1)
        }
    }
}

struct ActionPill: View {
    enum Style {
        case reply
        case review

        var title: String {
            switch self {
            case .reply: "Reply"
            case .review: "Review"
            }
        }

        var fill: Color {
            switch self {
            case .reply: .lfgPillReply
            case .review: .lfgPillReview
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .reply: "la.pill.reply"
            case .review: "la.pill.review"
            }
        }
    }

    let style: Style
    let sessionId: String

    var body: some View {
        if let destination = URL(string: "lfg://session/\(sessionId)") {
            Link(destination: destination) {
                Text(style.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(style.fill, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .accessibilityIdentifier(style.accessibilityIdentifier)
        }
    }
}

struct ElapsedTimeText: View {
    let since: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(compactElapsed(since: since, at: context.date))
        }
    }
}

struct SessionActivityHeader: View {
    let state: LFGSessionAttributes.ContentState

    var body: some View {
        HStack(spacing: 7) {
            SessionStateGlyph(state: state.normalizedState)
            StatusLabel(state: state.normalizedState)
            DirectoryTag(dir: state.dir)
            Spacer(minLength: 0)
            Text(state.host)
                .font(.footnote)
                .foregroundStyle(.lfgLabelHost)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct SessionActivityTitle: View {
    let title: String

    var body: some View {
        Text(title.isEmpty ? "Session" : title)
            .font(.system(size: 17, weight: .semibold))
            .lineSpacing(5)
            .kerning(-0.1)
            .foregroundStyle(.lfgLabelPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("la.title")
    }
}

struct SessionActivityFooter: View {
    let attributes: LFGSessionAttributes
    let state: LFGSessionAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if state.normalizedState == .finished,
               let added = state.added,
               let removed = state.removed,
               let files = state.files {
                DiffSummaryText(added: added, removed: removed, files: files)
                    .layoutPriority(1)
            } else if let footerText {
                Text(footerText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.lfgLabelTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }

            Spacer(minLength: 0)

            switch state.normalizedState {
            case .working:
                ElapsedTimeText(since: state.since)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.lfgLabelTertiary)
                    .monospacedDigit()
            case .blocked:
                ActionPill(style: .reply, sessionId: attributes.sessionId)
            case .finished:
                ActionPill(style: .review, sessionId: attributes.sessionId)
            }
        }
        .accessibilityIdentifier("la.footer")
    }

    private var footerText: String? {
        switch state.normalizedState {
        case .working:
            return state.subtitle?.nilIfEmpty
        case .blocked:
            return state.subtitle?.nilIfEmpty ?? "Waiting on your reply"
        case .finished:
            return diffSummary(added: state.added, removed: state.removed, files: state.files)
        }
    }
}

struct DiffSummaryText: View {
    let added: Int
    let removed: Int
    let files: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("+\(added)")
                .foregroundStyle(.lfgDiffAdded)
            Text("−\(removed)")
                .foregroundStyle(.lfgDiffRemoved)
            Text("· \(files) Files")
                .foregroundStyle(.lfgLabelTertiary)
        }
        .font(.system(size: 14, weight: .regular))
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

struct SessionActivityCard: View {
    let attributes: LFGSessionAttributes
    let state: LFGSessionAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionActivityHeader(state: state)
            SessionActivityTitle(title: state.title)
                .padding(.top, 5)
            SessionActivityFooter(attributes: attributes, state: state)
                .padding(.top, 8)
        }
        .padding(.top, 12)
        .padding(.leading, 15)
        .padding(.trailing, 15)
        .padding(.bottom, 13)
        .accessibilityIdentifier("la.card.\(state.normalizedState.accessibilityName)")
    }
}

func compactElapsed(since: Double, at date: Date) -> String {
    guard since > 0 else { return "now" }
    let seconds = max(0, Int(date.timeIntervalSince1970 - since))
    guard seconds >= 60 else { return "now" }

    let minutes = seconds / 60
    guard minutes >= 60 else { return "\(minutes)m" }

    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
}

func diffSummary(added: Int?, removed: Int?, files: Int?) -> String? {
    guard let added, let removed, let files else { return nil }
    return "+\(added) −\(removed) · \(files) Files"
}

extension LFGSessionAttributes.ContentState {
    var normalizedState: SessionActivityState {
        SessionActivityState(rawValue: state.lowercased()) ?? .working
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// Declared on `Color` so `Color.lfgX` and Color-typed positions work, then
// re-exposed on `ShapeStyle` so the leading-dot form resolves in
// `.foregroundStyle(.lfgX)` / `.fill(.lfgX)` — a plain `extension Color` does
// NOT reach those, which is what broke the first build.
extension ShapeStyle where Self == Color {
    static var lfgCardBackground: Color { .lfgCardBackground }
    static var lfgLabelPrimary: Color { .lfgLabelPrimary }
    static var lfgLabelSecondary: Color { .lfgLabelSecondary }
    static var lfgLabelTertiary: Color { .lfgLabelTertiary }
    static var lfgLabelQuaternary: Color { .lfgLabelQuaternary }
    static var lfgLabelHost: Color { .lfgLabelHost }
    static var lfgStateWorking: Color { .lfgStateWorking }
    static var lfgStateNeedsInput: Color { .lfgStateNeedsInput }
    static var lfgGlyphAppFill: Color { .lfgGlyphAppFill }
    static var lfgGlyphAppDot: Color { .lfgGlyphAppDot }
    static var lfgGlyphAlertTile: Color { .lfgGlyphAlertTile }
    static var lfgGlyphAlertStroke: Color { .lfgGlyphAlertStroke }
    static var lfgPillReply: Color { .lfgPillReply }
    static var lfgPillReview: Color { .lfgPillReview }
    static var lfgDiffAdded: Color { .lfgDiffAdded }
    static var lfgDiffRemoved: Color { .lfgDiffRemoved }
}

extension Color {
    static let lfgCardBackground = Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255).opacity(0.72)
    static let lfgLabelPrimary = Color.white
    static let lfgLabelSecondary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.70)
    static let lfgLabelTertiary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.60)
    static let lfgLabelQuaternary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.45)
    static let lfgLabelHost = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.40)
    static let lfgStateWorking = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let lfgStateNeedsInput = Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)
    static let lfgGlyphAppFill = Color.white
    static let lfgGlyphAppDot = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    static let lfgGlyphAlertTile = Color(red: 58 / 255, green: 42 / 255, blue: 34 / 255)
    static let lfgGlyphAlertStroke = Color(red: 240 / 255, green: 115 / 255, blue: 63 / 255)
    static let lfgPillReply = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255).opacity(0.90)
    static let lfgPillReview = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.36)
    static let lfgDiffAdded = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let lfgDiffRemoved = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
}

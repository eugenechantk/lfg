import SwiftUI

struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: 0.50, y: 0.00),
            CGPoint(x: 0.60, y: 0.40),
            CGPoint(x: 1.00, y: 0.50),
            CGPoint(x: 0.60, y: 0.60),
            CGPoint(x: 0.50, y: 1.00),
            CGPoint(x: 0.40, y: 0.60),
            CGPoint(x: 0.00, y: 0.50),
            CGPoint(x: 0.40, y: 0.40),
        ]

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: point(first, in: rect))
        for point in points.dropFirst() {
            path.addLine(to: self.point(point, in: rect))
        }
        path.closeSubpath()
        return path
    }

    private func point(_ unitPoint: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + unitPoint.x * rect.width,
            y: rect.minY + unitPoint.y * rect.height
        )
    }
}

struct LFGSparkMark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            FourPointStar()
                .fill(NewSessionPalette.brandOrange)
                .frame(width: 36, height: 36)
                .offset(x: 16, y: 6)

            FourPointStar()
                .fill(NewSessionPalette.brandOrange)
                .frame(width: 17, height: 17)
                .offset(x: 5, y: 1)
        }
        // `.offset` is draw-time only, so the ZStack sizes to its 36x36 child and
        // this frame would CENTRE that child before the offsets apply — pushing the
        // whole composition ~11pt right and ~7pt down. Anchoring top-leading makes
        // the offsets absolute within the 58x48 box, as the design's CSS is.
        .frame(width: 58, height: 48, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

struct SelectionCheck: View {
    let selected: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(NewSessionPalette.accent)
            .frame(width: 18, height: 18)
            .opacity(selected ? 1 : 0)
            .accessibilityHidden(true)
    }
}

struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(NewSessionPalette.separator)
            .frame(height: 1)
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: String
    var topPadding: CGFloat = 9
    var bottomPadding: CGFloat = 5

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(NewSessionPalette.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
    }
}

struct CircularBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Sized from the design's DRAWN path (5x11), not its 24-unit SVG box —
            // the box includes inset padding, which is what made every glyph oversized.
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NewSessionPalette.labelPrimary)
                .frame(width: 38, height: 38)
                .background(NewSessionPalette.surfaceRaised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("newSession.back")
    }
}

struct NavRow: View {
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CircularBackButton(action: onBack)

            Text("New session")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NewSessionPalette.labelPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("newSession.title")

            Color.clear
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
        }
        .frame(height: 38)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

struct EmptyDraftState: View {
    var body: some View {
        VStack(spacing: 0) {
            LFGSparkMark()

            Text("Describe a task to start")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NewSessionPalette.labelPrimary)
                .padding(.top, 8)

            Text("Your first message kicks off the session.")
                .font(.system(size: 15))
                .foregroundStyle(NewSessionPalette.labelSecondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("newSession.emptyState")
    }
}

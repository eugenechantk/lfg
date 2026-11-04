import SwiftUI

/// One native list bar. Features provide their own menu actions, never geometry.
struct ListHeaderToolbar<Header: View, Options: View>: ToolbarContent {
    let searchLabel: String
    let searchIdentifier: String
    var onSearch: (() -> Void)?
    @ViewBuilder var header: () -> Header
    @ViewBuilder var options: () -> Options

    @ToolbarContentBuilder var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { header() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { header() }
        }
        if let onSearch {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onSearch) {
                    BoardGlyph(kind: .search, lineWidth: 2).frame(width: 21, height: 21)
                }
                .accessibilityLabel(searchLabel)
                .accessibilityIdentifier(searchIdentifier)
            }
        }
        ToolbarItem(placement: .primaryAction) { options() }
    }
}

struct ListOptionsLabel: View {
    let title: String
    var body: some View {
        BoardGlyph(kind: .more).frame(width: 20, height: 20)
            .foregroundStyle(Color(.label))
            .accessibilityLabel(title)
    }
}

struct ListCreateButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Wrap the button, not its label: the bar's glass must not eat the tap.
        .glassOrRaised(in: Circle(), interactive: true)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// Native material and hit area match Back on both conversation screens.
struct ConversationToolbar<Heading: View>: ToolbarContent {
    let optionsTitle: String
    let optionsIdentifier: String
    var optionsEnabled = true
    let onOptions: () -> Void
    @ViewBuilder var heading: () -> Heading

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) { heading() }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onOptions) {
                Image(uiImage: SessionOptionsGlyph.image)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .frame(width: 44, height: 44)
            .disabled(!optionsEnabled)
            .accessibilityLabel(optionsTitle)
            .accessibilityIdentifier(optionsIdentifier)
        }
    }
}

struct SidebarToggleToolbar: ToolbarContent {
    @Binding var visibility: NavigationSplitViewVisibility
    let title: String
    let identifier: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    visibility = visibility == .detailOnly ? .doubleColumn : .detailOnly
                }
            } label: { Image(systemName: "sidebar.leading") }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(visibility == .detailOnly ? "Show \(title)" : "Hide \(title)")
            .help(visibility == .detailOnly ? "Show \(title)" : "Hide \(title)")
        }
    }
}

struct ConversationHeaderFade: View {
    let height: CGFloat
    var body: some View {
        ChromeFade(edge: .top, barHeight: height).offset(y: -height)
    }
}

struct ConversationComposerFade: View {
    let bottomSafeAreaInset: CGFloat
    var body: some View {
        GeometryReader { proxy in
            ChromeFade(edge: .bottom, barHeight: proxy.size.height + bottomSafeAreaInset)
                .offset(y: -ChromeFade.tail(.bottom))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ComposerModelLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Text(text).lineLimit(1)
            BoardGlyph(kind: .chevronDown, lineWidth: 3).frame(width: 9, height: 9)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(S2.chipInk)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(S2.chip, in: Capsule())
        .contentShape(Capsule())
    }
}

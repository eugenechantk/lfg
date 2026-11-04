import SwiftUI
import LFGCore

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

/// Sessions and durable chats share the complete native header, including
/// title disclosure and navigation transitions, rather than only its label.
struct ConversationNavigationHeader: ViewModifier {
    let title: String
    let fullTitle: String
    let status: SessionStatusLine.State
    let queued: Int
    let hostLabel: String?
    let project: String?
    @Binding var showingFullTitle: Bool
    let optionsTitle: String
    let optionsIdentifier: String
    var optionsEnabled = true
    var titleIdentifier = "sessionTitle"
    var statusIdentifier = "sessionStatusLine"
    var disclosureIdentifier = "fullTitleCard"
    var titleHint = "Shows the full session title"
    let onOptions: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ConversationToolbar(optionsTitle: optionsTitle, optionsIdentifier: optionsIdentifier,
                    optionsEnabled: optionsEnabled, onOptions: onOptions) {
                    SessionTitleBarContent(title: title, status: status, queued: queued,
                        hostLabel: hostLabel, project: project, titleIdentifier: titleIdentifier,
                        statusIdentifier: statusIdentifier, titleHint: titleHint) {
                        withAnimation(.easeOut(duration: 0.18)) { showingFullTitle.toggle() }
                    }
                }
            }
            .overlay(alignment: .top) {
                if showingFullTitle {
                    ConversationTitleCard(title: fullTitle) {
                        withAnimation(.easeOut(duration: 0.18)) { showingFullTitle = false }
                    }.accessibilityIdentifier(disclosureIdentifier)
                }
            }
    }
}

private struct ConversationTitleCard: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.leading)
            .lineLimit(12)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
    }
}

/// The same header moves into the transcript when the iPad reader is docked.
struct ConversationPaneHeader<Heading: View>: View {
    let listTitle: String
    let listIdentifier: String
    var needsInputCount = 0
    let optionsTitle: String
    let optionsIdentifier: String
    let onShowList: () -> Void
    let onOptions: () -> Void
    @ViewBuilder var heading: () -> Heading

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShowList) {
                Image(systemName: "sidebar.leading").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).glassOrRaised(in: Circle(), interactive: true)
            .overlay(alignment: .topTrailing) {
                if needsInputCount > 0 {
                    Text("\(needsInputCount)").font(.caption2.bold())
                        .padding(4).background(.orange, in: Circle())
                }
            }
            .accessibilityLabel(listTitle).accessibilityIdentifier(listIdentifier)
            heading().frame(maxWidth: .infinity)
            Button(action: onOptions) {
                Image(uiImage: SessionOptionsGlyph.image).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).glassOrRaised(in: Circle(), interactive: true)
            .accessibilityLabel(optionsTitle).accessibilityIdentifier(optionsIdentifier)
        }.padding(.horizontal, 10)
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

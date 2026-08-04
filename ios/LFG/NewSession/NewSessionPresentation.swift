import SwiftUI

/// Presents the same new-session surface with the idiom-specific navigation
/// required by the split-view shell.
private struct NewSessionPresentationModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selection: String?
    @Binding var isPresented: Bool
    @Binding var autofocusComposer: Bool

    /// The id handed up by a create, held until the create screen is actually
    /// gone. See `applyPendingSelection`.
    @State private var pendingSelection: String?

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: compactPresentation) {
                destination
            }
            .fullScreenCover(
                isPresented: regularPresentation,
                onDismiss: resetPresentation
            ) {
                destination
            }
    }

    private var compactPresentation: Binding<Bool> {
        Binding(
            get: { isPresented && horizontalSizeClass != .regular },
            set: { updatePresentation($0) }
        )
    }

    private var regularPresentation: Binding<Bool> {
        Binding(
            get: { isPresented && horizontalSizeClass == .regular },
            set: { updatePresentation($0) }
        )
    }

    private var destination: some View {
        NewSessionView(autofocusComposer: autofocusComposer) { newID in
            // Deliberately NOT `selection = newID`. The create screen dismisses
            // itself in this same runloop turn, and in compact width it is a push
            // on the very stack that `selection` drives — a selection change made
            // during that in-flight transition is swallowed. The optimistic
            // session was in the store immediately, but the detail only opened
            // seconds later, when the server's create response re-requested it,
            // which read as "send does nothing, then it jumps".
            pendingSelection = newID
        }
    }

    private func updatePresentation(_ newValue: Bool) {
        isPresented = newValue
        if !newValue {
            autofocusComposer = false
            applyPendingSelection()
        }
    }

    private func resetPresentation() {
        isPresented = false
        autofocusComposer = false
        applyPendingSelection()
    }

    /// Open the just-created session once the create screen's dismissal has been
    /// committed. One main-actor hop is the whole difference between a selection
    /// the navigation stack drops and a normal push.
    private func applyPendingSelection() {
        guard let id = pendingSelection else { return }
        pendingSelection = nil
        Task { @MainActor in
            await Task.yield()
            selection = id
        }
    }
}

extension View {
    func newSessionPresentation(
        selection: Binding<String?>,
        isPresented: Binding<Bool>,
        autofocusComposer: Binding<Bool>
    ) -> some View {
        modifier(NewSessionPresentationModifier(
            selection: selection,
            isPresented: isPresented,
            autofocusComposer: autofocusComposer
        ))
    }
}

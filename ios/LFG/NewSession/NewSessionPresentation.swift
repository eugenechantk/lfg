import LFGCore
import SwiftUI

/// Presents the new-session surface as a full-screen cover, in BOTH size classes.
///
/// It used to be a `navigationDestination` push in compact width, which put the
/// create screen on the very same navigation stack the session detail is pushed
/// onto (`List(selection:)` inside the split view's sidebar drives that push).
/// Dismissing it therefore raced the push of the session you just created, and
/// SwiftUI resolved that race differently run to run:
///
///   * the pop read as "the stack returned to its root", so the split view wrote
///     `selection = nil` ~175ms after the create set it — leaving an orphaned
///     "No session selected" screen pushed on top of the real one, or
///   * both writes landed as pushes, and one send produced two stacked detail
///     screens.
///
/// A cover is not on the stack, and `onDismiss` fires once it is fully gone — so
/// the selection lands on an idle stack and pushes exactly one detail.
private struct NewSessionPresentationModifier: ViewModifier {
    @Binding var selection: String?
    @Binding var isPresented: Bool
    @Binding var autofocusComposer: Bool
    @Binding var prefill: NewSessionPrefill?
    var purpose: SessionCreationPurpose

    /// The id handed up by a create, held until the create screen is actually
    /// gone. See `applyPendingSelection`.
    @State private var pendingSelection: String?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented, onDismiss: resetPresentation) {
                NewSessionView(autofocusComposer: autofocusComposer, purpose: purpose, prefill: $prefill) { newID in
                    // Deliberately NOT `selection = newID`. The create screen is
                    // dismissing in this same runloop turn; a selection change made
                    // during that in-flight transition is swallowed. The optimistic
                    // session was in the store immediately, but the detail only
                    // opened seconds later, when the server's create response
                    // re-requested it, which read as "send does nothing, then it
                    // jumps".
                    pendingSelection = newID
                }
            }
    }

    private func resetPresentation() {
        autofocusComposer = false
        // A link's prefill is one-shot: dismissed unused, it must not resurface
        // the next time "+" opens this screen.
        prefill = nil
        applyPendingSelection()
    }

    /// Open the just-created session once the create screen's dismissal has been
    /// committed. One main-actor hop keeps the assignment out of UIKit's dismissal
    /// transaction — mutating navigation state inside one is undefined behavior.
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
        autofocusComposer: Binding<Bool>,
        prefill: Binding<NewSessionPrefill?>,
        purpose: SessionCreationPurpose = .conversation
    ) -> some View {
        modifier(NewSessionPresentationModifier(
            selection: selection,
            isPresented: isPresented,
            autofocusComposer: autofocusComposer,
            prefill: prefill,
            purpose: purpose
        ))
    }
}

/// A one-shot request from an `lfg://new` link to open New Session with the
/// composer (and optionally the directory) filled in. The id makes a second link
/// with identical text still count as a new request.
struct NewSessionPrefill: Equatable, Identifiable {
    let id = UUID()
    let link: NewSessionLink
}

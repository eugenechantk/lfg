import SwiftUI

/// Presents the same new-session surface with the idiom-specific navigation
/// required by the split-view shell.
private struct NewSessionPresentationModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selection: String?
    @Binding var isPresented: Bool
    @Binding var autofocusComposer: Bool

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
            selection = newID
        }
    }

    private func updatePresentation(_ newValue: Bool) {
        isPresented = newValue
        if !newValue {
            autofocusComposer = false
        }
    }

    private func resetPresentation() {
        isPresented = false
        autofocusComposer = false
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

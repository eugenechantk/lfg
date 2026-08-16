import SwiftUI
import LFGCore

/// One picked item waiting to be sent — a photo, a video, or any file at all.
///
/// `preview` is only populated for things that *look* like something. Everything
/// else renders as a named chip, which is the honest presentation: a blank grey
/// square labelled nothing is worse than an icon and a filename.
struct ComposerAttachment: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let meta: AttachmentMeta
    let preview: UIImage?

    var filename: String { meta.filename }
    var kind: AttachmentKind { meta.kind }

    static func == (lhs: ComposerAttachment, rhs: ComposerAttachment) -> Bool { lhs.id == rhs.id }
}

/// Floating message bar: a growing multiline input with the attach + send
/// buttons on a row *below* the input area. Reused by the live session view and
/// the new-session draft screen.
struct MessageComposer: View {
    @Binding var text: String
    var placeholder: String = "Message"
    var sending: Bool = false
    var autofocus = false
    /// Receives the trimmed text and any picked attachments.
    let onSend: (String, [ComposerAttachment]) -> Void

    @State private var tray = AttachmentTray()
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tray.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tray.isEmpty { AttachmentChips(tray: tray) }

            // Growing input area.
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .font(.body)

            // Controls row, below the input.
            HStack(spacing: 14) {
                // A menu rather than a direct PhotosPicker: "attach" now means two
                // different system pickers and the choice has to be the user's.
                Menu {
                    AttachmentMenuItems(tray: tray)
                } label: {
                    if tray.isLoading {
                        ProgressView().controlSize(.small).frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "paperclip").font(.title3)
                    }
                }
                .tint(.secondary)
                .accessibilityLabel("Attach")
                .accessibilityIdentifier("composer.attach")
                .disabled(tray.isLoading)

                Spacer()

                Button(action: submit) {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(canSend ? Color.accentColor : Color.gray.opacity(0.3), in: Circle())
                            .foregroundStyle(.white)
                    }
                }
                .disabled(!canSend || sending)
                .accessibilityIdentifier("composer.send")
            }
        }
        .padding(12)
        .modifier(GlassPanel(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .attachmentPickers(tray)
        .task(id: autofocus) {
            guard autofocus else { return }
            await Task.yield()
            focused = true
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        onSend(trimmed, tray.items)
        text = ""
        tray.clear()
    }
}

/// Resign whatever is currently first responder.
///
/// The composer's focus is a private `@FocusState` (it has to be — the composer
/// is reused by the new-session screen, which drives its own autofocus), so a
/// sibling view like the transcript can't flip it directly. Sending
/// `resignFirstResponder` up the responder chain dismisses the keyboard and
/// SwiftUI syncs the `@FocusState` back to `false` for us.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Liquid Glass panel on iOS 26+, with a material fallback for iOS 17–25.
struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.glassOrRaised(
            in: RoundedRectangle(cornerRadius: cornerRadius),
            fallback: Color(.secondarySystemBackground)
        )
    }
}

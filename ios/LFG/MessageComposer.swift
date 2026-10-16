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
    /// Increment to focus the input after an external action fills its binding.
    var focusRequest = 0
    /// The S2 session-view layout (board `s2-view`): a solid surface, a chip
    /// after the paperclip, and Stop in place of Send while the agent works.
    var s2 = false
    /// Shown after the paperclip in S2 mode (the model + effort chip).
    var accessory: AnyView? = nil
    /// When set and nothing is typed or attached, the send button is Stop.
    var onStop: (() -> Void)? = nil
    /// Space under the bar. S2 sits lower while the keyboard is down.
    var bottomPadding: CGFloat = 8
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Receives the trimmed text and any picked attachments.
    let onSend: (String, [ComposerAttachment]) -> Void

    @State private var tray = AttachmentTray()
    @FocusState private var focused: Bool

    private var canSend: Bool {
        OutgoingAttachmentMessage.canSend(text: text, attachmentCount: tray.items.count)
    }

    private var showsStop: Bool {
        onStop != nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tray.isEmpty
    }

    var body: some View {
        Group {
            if s2 { s2Bar } else { classicBar }
        }
        .attachmentPickers(tray)
        .task(id: autofocus) {
            guard autofocus else { return }
            await Task.yield()
            focused = true
        }
        .onChange(of: focusRequest) { _, _ in
            focused = true
        }
    }

    private var s2Bar: some View {
        // Fixed gaps, no Spacer: inside a safe-area inset a Spacer takes every
        // point it is offered and the bar fills the screen. Board: 11 + 22-pt
        // line + 19 + 34-pt buttons + 10 = 96pt for one line of text.
        VStack(alignment: .leading, spacing: 0) {
            if !tray.isEmpty { AttachmentChips(tray: tray).padding(.bottom, 8) }

            TextField(text: $text, prompt: Text(placeholder).foregroundStyle(S2.metaInk), axis: .vertical) {
                Text(placeholder)
            }
            .lineLimit(1...8)
            .focused($focused)
            .font(.system(size: 17))
            .foregroundStyle(S2.ink)
            .accessibilityIdentifier("composer.message")
            .onChange(of: focused) { _, isFocused in
                onFocusChange(isFocused)
            }

            HStack(spacing: 8) {
                Menu {
                    AttachmentMenuItems(tray: tray)
                } label: {
                    Group {
                        if tray.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            PaperclipGlyph()
                                .frame(width: 22, height: 22)
                                .foregroundStyle(S2.secondaryInk)
                        }
                    }
                    .frame(width: 22, height: 34)
                    // A finger-sized target around a 22pt glyph.
                    .contentShape(Rectangle().inset(by: -8))
                }
                .accessibilityLabel("Attach")
                .accessibilityIdentifier("composer.attach")
                .disabled(tray.isLoading)

                if let accessory { accessory }

                Spacer(minLength: 0)

                if showsStop, let onStop {
                    Button(action: onStop) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(S2.stopSquare)
                            .frame(width: 11, height: 11)
                            .frame(width: 34, height: 34)
                            .background(S2.stopDisc, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop the current turn")
                    .accessibilityIdentifier("composer.stop")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Button(action: submit) {
                        Group {
                            if sending {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                SendArrowGlyph()
                                    .frame(width: 16, height: 16)
                                    .foregroundStyle(canSend ? Color.white : S2.metaInk)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(canSend ? S2.send : S2.color(dark: 0x3A3A3C, light: 0xE5E5EA), in: Circle())
                    }
                    .buttonStyle(.plain)
                    // Not `.disabled`: that dims the board's #3A3A3C to half strength.
                    .allowsHitTesting(canSend && !sending)
                    .accessibilityAddTraits(canSend && !sending ? [] : .isStaticText)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("composer.send")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: showsStop)
            .padding(.top, 18)
        }
        // SwiftUI's 17pt line is ~2pt shorter than the board's 22pt, so the
        // text starts 2pt lower to sit where the board's does.
        .padding(EdgeInsets(top: 13, leading: 16, bottom: 10, trailing: 10))
        .background(S2.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(S2.surfaceBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, bottomPadding)
    }

    private var classicBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tray.isEmpty { AttachmentChips(tray: tray) }

            // Growing input area.
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .font(.body)
                .accessibilityIdentifier("composer.message")
                .onChange(of: focused) { _, isFocused in
                    onFocusChange(isFocused)
                }

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
                        Image(systemName: "paperclip")
                            .font(.title3)
                            // The glyph itself is only about 23×25pt. Keeping that
                            // as the Menu label made the real tap target just as
                            // small, so ordinary finger taps around the paperclip
                            // looked unresponsive. Preserve the icon's leading
                            // position while giving the control a HIG-sized target.
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
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
        .padding(.bottom, bottomPadding)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        // Clear BEFORE handing off, not after.
        //
        // `onSend` runs synchronously and mutates observable store state, parent
        // `@State`, and (in the transcript) a scroll animation — any of which can
        // re-render this composer inside the same transaction. A `TextField` with
        // `axis: .vertical` is a UITextView underneath, and on that re-render it
        // re-seeds itself from the binding, which still held the old text. The
        // `text = ""` that followed then landed on a text session that had already
        // decided what it was showing, so the field kept the message — sometimes,
        // depending on whether the hand-off happened to force a layout pass.
        //
        // Settling our own state first makes the composer empty before anyone
        // else can react, so there is no stale value left to re-seed from.
        let items = tray.items
        text = ""
        tray.clear()
        onSend(trimmed, items)
        #if DEBUG
        // `LFG_COMPOSER_FORCE_WRITEBACK=1` re-creates the device failure on demand —
        // the sent text landing back in the binding after the clear — so the probe
        // below can be exercised in a simulator that never shows it naturally.
        if ProcessInfo.processInfo.environment["LFG_COMPOSER_FORCE_WRITEBACK"] == "1" {
            let binding = $text
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                binding.wrappedValue = trimmed
            }
        }
        #endif
        ComposerClearProbe.verify(sent: trimmed, binding: $text)
    }
}

/// Checks, shortly after a send, that the field really is empty — and says so in
/// the connection log when it is not.
///
/// The composer still keeps a sent message on screen "a lot of the time" on
/// device (2026-09-21), and it does not reproduce in a simulator driven without
/// the software keyboard. Two different failures look identical to the eye: the
/// binding is empty and the UITextView behind `TextField(axis: .vertical)` never
/// repainted, or something (a pending autocorrection, marked text from swipe or
/// dictation) wrote the message back into the binding after the clear. The probe
/// reads all three — binding, the text view's own text, marked text — so the
/// next occurrence names its mechanism instead of being guessed at. It also
/// repairs the field, but only when what is left is exactly the message that was
/// just sent: anything else is the user already typing the next one.
///
/// Lengths only; message text never goes in the log.
@MainActor
enum ComposerClearProbe {
    static func verify(sent: String, binding: Binding<String>) {
        guard !sent.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            let view = firstResponderTextView()
            let bound = binding.wrappedValue
            let shown = view?.text ?? ""
            let boundIsSent = bound.trimmingCharacters(in: .whitespacesAndNewlines) == sent
            let shownIsSent = shown.trimmingCharacters(in: .whitespacesAndNewlines) == sent
            guard boundIsSent || shownIsSent else { return }
            ConnectionLog.shared.log(
                .send,
                "composer not cleared: sent=\(sent.count) binding=\(bound.count) view=\(view == nil ? "none" : String(shown.count)) marked=\(view?.markedTextRange != nil)"
            )
            if boundIsSent { binding.wrappedValue = "" }
            if shownIsSent, let view {
                view.unmarkText()
                view.text = ""
            }
        }
    }

    private static func firstResponderTextView() -> UITextView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows where window.isKeyWindow {
            if let found = firstResponder(in: window) { return found }
        }
        return nil
    }

    private static func firstResponder(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView, textView.isFirstResponder { return textView }
        for sub in view.subviews {
            if let found = firstResponder(in: sub) { return found }
        }
        return nil
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
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Regular glass keeps the transcript perceptible as movement and
            // color without letting sharp text compete with the input itself.
            content.glassEffect(
                .chrome(colorScheme),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

/// The boards' send arrow: "M12 19V5M5 12l7-7 7 7" in a 24-unit box, 3pt stroke.
struct SendArrowGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            Path { p in
                p.move(to: CGPoint(x: 12 * k, y: 19 * k)); p.addLine(to: CGPoint(x: 12 * k, y: 5 * k))
                p.move(to: CGPoint(x: 5 * k, y: 12 * k)); p.addLine(to: CGPoint(x: 12 * k, y: 5 * k))
                p.addLine(to: CGPoint(x: 19 * k, y: 12 * k))
            }
            .stroke(style: StrokeStyle(lineWidth: 3 * k, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// The boards' paperclip (`s2-view`): "M20.5 11.5l-8.2 8.2a5 5 0 0 1-7.1-7.1
/// l8.6-8.6a3.4 3.4 0 0 1 4.8 4.8l-8.6 8.6a1.7 1.7 0 0 1-2.4-2.4l7.9-7.9",
/// 24-unit box, 1.7 stroke. Each arc is a half circle.
struct PaperclipGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 24
            let pt = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * k, y: y * k) }
            Path { p in
                p.move(to: pt(20.5, 11.5))
                p.addLine(to: pt(12.3, 19.7))
                p.addArc(center: pt(8.75, 16.15), radius: 5.02 * k,
                         startAngle: .degrees(45), endAngle: .degrees(225), clockwise: false)
                p.addLine(to: pt(13.8, 4.0))
                p.addArc(center: pt(16.2, 6.4), radius: 3.39 * k,
                         startAngle: .degrees(225), endAngle: .degrees(405), clockwise: false)
                p.addLine(to: pt(10.0, 17.4))
                p.addArc(center: pt(8.8, 16.2), radius: 1.7 * k,
                         startAngle: .degrees(45), endAngle: .degrees(225), clockwise: false)
                p.addLine(to: pt(15.5, 7.1))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.7 * k, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

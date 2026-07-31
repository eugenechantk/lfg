import PhotosUI
import SwiftUI

struct ConfigChip: View {
    enum Kind {
        case directory
        case host(isReachable: Bool)
        case model
    }

    let label: String
    let kind: Kind
    let isActive: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Base spacing 5 for dot->label; the label->chevron gap is tuned
            // separately below because the SF Symbol carries its own bearing.
            HStack(spacing: 5) {
                if case let .host(isReachable) = kind {
                    Circle()
                        .fill(isReachable ? NewSessionPalette.statusOK : NewSessionPalette.statusWarn)
                        .frame(width: 7, height: 7)
                }

                Text(label)
                    .font(chipFont)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)

                // Sized from the design's DRAWN path (7.22 x 4.23), re-measured by
                // supersampled rasterisation — an earlier 7pt guess was 18% short.
                Image(systemName: isActive ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.leading, 0.75)
                    .foregroundStyle(isActive ? NewSessionPalette.accent : NewSessionPalette.labelSecondary)
            }
            .contentShape(Rectangle())
        }
        .glassButtonStyleOrPlain()
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var chipFont: Font {
        switch kind {
        case .directory:
            .system(size: 15, weight: .semibold)
        case .host, .model:
            .system(size: 15)
        }
    }

    private var labelColor: Color {
        switch kind {
        case .directory:
            return NewSessionPalette.labelPrimary
        case let .host(isReachable):
            guard isReachable else { return NewSessionPalette.statusWarn }
            // The design brightens the host label 0.6 -> 0.85 while its sheet is open.
            return isActive ? NewSessionPalette.modelChipLabel : NewSessionPalette.labelSecondary
        case .model:
            return NewSessionPalette.modelChipLabel
        }
    }
}

struct NewSessionComposer: View {
    @Binding var text: String
    @Binding var activeSheet: ActiveSheet?

    let directoryLabel: String
    let hostLabel: String
    let hostIsReachable: Bool
    let modelLabel: String
    var sending = false
    var autofocus = false
    let onSend: (String, [ComposerAttachment]) -> Void

    @State private var attachments: [ComposerAttachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerLineSpacing: CGFloat {
        24 - UIFont.systemFont(ofSize: 17).lineHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ConfigChip(
                    label: directoryLabel,
                    kind: .directory,
                    isActive: activeSheet == .directory,
                    accessibilityIdentifier: "newSession.chip.directory"
                ) {
                    toggle(.directory)
                }

                ConfigChip(
                    label: hostLabel,
                    kind: .host(isReachable: hostIsReachable),
                    isActive: activeSheet == .host,
                    accessibilityIdentifier: "newSession.chip.host"
                ) {
                    toggle(.host)
                }
            }

            if !attachments.isEmpty {
                thumbnails
                    .padding(.top, 12)
            }

            TextField(
                "",
                text: $text,
                prompt: Text("Describe the task...")
                    .foregroundStyle(NewSessionPalette.placeholder),
                axis: .vertical
            )
            .lineLimit(1 ... 8)
            .font(.system(size: 17))
            .lineSpacing(composerLineSpacing)
            .foregroundStyle(NewSessionPalette.labelPrimary)
            .tint(NewSessionPalette.accent)
            .focused($focused)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            // The TextField only draws ~21pt tall, so without these a tap anywhere
            // in the lower two-thirds of the design's 68pt text block was swallowed
            // by the card instead of focusing the field — and 21pt is under the
            // 44pt HIG minimum target. contentShape makes the whole block hittable.
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .padding(.top, attachments.isEmpty ? 12 : 8)
            .accessibilityIdentifier("newSession.input")

            HStack(spacing: 14) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    // Design drawn ink is 17.06pt; at this weight SF renders ~0.78pt
                    // of ink per pt of size, so 22 lands it. The 26pt slot is the
                    // design's touch area and stays as-is.
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(NewSessionPalette.attachIcon)
                        .frame(width: 26, height: 26)
                }
                .glassButtonStyleOrPlain()
                .accessibilityLabel("Attach image")
                .accessibilityIdentifier("newSession.attach")

                ConfigChip(
                    label: modelLabel,
                    kind: .model,
                    isActive: activeSheet == .model,
                    accessibilityIdentifier: "newSession.chip.model"
                ) {
                    toggle(.model)
                }

                Spacer(minLength: 0)

                Button(action: submit) {
                    // Sized to the design's STROKED ink height (10.69) — the SVG path
                    // bbox is 8.5x9.2 but is stroked at 2.2, so the drawn ink is
                    // larger than the path. Matching height, not width: arrow.up's
                    // head is intrinsically narrower than the design's glyph.
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : NewSessionPalette.idleSendIcon)
                        .frame(width: 32, height: 32)
                        .glassOrRaised(
                            in: Circle(),
                            fallback: canSend ? NewSessionPalette.accent : NewSessionPalette.surfaceControl,
                            tint: canSend ? NewSessionPalette.accent : nil,
                            interactive: true
                        )
                }
                .buttonStyle(.plain)
                // NOT `.disabled()` — SwiftUI dims a disabled plain-button label to
                // ~50%, which is exactly the measured (36,36,38) vs #2C2C2E delta.
                // The design renders the idle state undimmed, so suppress input
                // instead of disabling. `submit()` also guards on canSend.
                .allowsHitTesting(canSend && !sending)
                .accessibilityLabel("Start session")
                .accessibilityIdentifier("newSession.send")
            }
            .padding(.top, 18)
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .glassOrRaised(
            in: RoundedRectangle(cornerRadius: 24),
            fallback: NewSessionPalette.surfaceRaised
        )
        // No identifier on the card container — same propagation trap as the screen
        // root: it overwrote the chip/input/attach/send ids with "newSession.composer".
        .onChange(of: pickerItems) { _, items in
            Task { await load(items) }
        }
        .task(id: autofocus) {
            guard autofocus else { return }
            await Task.yield()
            focused = true
        }
    }

    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: attachment.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .offset(x: 5, y: -5)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle(_ sheet: ActiveSheet) {
        focused = false
        activeSheet = activeSheet == sheet ? nil : sheet
    }

    private func submit() {
        guard canSend, !sending else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSend(trimmed, attachments)
        text = ""
        attachments = []
        pickerItems = []
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [ComposerAttachment] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data)
            {
                loaded.append(ComposerAttachment(image: image, data: image.pngData() ?? data))
            }
        }
        let result = loaded
        await MainActor.run {
            attachments.append(contentsOf: result)
            pickerItems = []
        }
    }
}

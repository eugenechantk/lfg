import SwiftUI
import PhotosUI
import LFGCore

struct ComposerAttachment: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    let data: Data            // PNG bytes for upload
}

/// Floating message bar: a growing multiline input with the attach + send
/// buttons on a row *below* the input area. Reused by the live session view and
/// the new-session draft screen.
struct MessageComposer: View {
    @Binding var text: String
    var placeholder: String = "Message"
    var sending: Bool = false
    /// Receives the trimmed text and any picked image attachments.
    let onSend: (String, [ComposerAttachment]) -> Void

    @State private var attachments: [ComposerAttachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty { thumbnails }

            // Growing input area.
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .font(.body)

            // Controls row, below the input.
            HStack(spacing: 14) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                    Image(systemName: "paperclip").font(.title3)
                }
                .tint(.secondary)

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
            }
        }
        .padding(12)
        .modifier(GlassPanel(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: pickerItems) { _, items in Task { await load(items) } }
    }

    private var thumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { att in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: att.image)
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button {
                            attachments.removeAll { $0.id == att.id }
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

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        onSend(trimmed, attachments)
        text = ""
        attachments = []
        pickerItems = []
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [ComposerAttachment] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                // Prefer PNG bytes; fall back to the original data if conversion fails.
                loaded.append(ComposerAttachment(image: img, data: img.pngData() ?? data))
            }
        }
        let result = loaded
        await MainActor.run { attachments.append(contentsOf: result); pickerItems = [] }
    }
}

/// Liquid Glass panel on iOS 26+, with a material fallback for iOS 17–25.
struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.quaternary))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }
}

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import LFGCore

// MARK: - Attaching files to an outgoing message
//
// Two composers send messages — the live session bar and the new-session draft —
// and both need the whole attach apparatus: a menu, two system pickers, byte
// loading, size limits, and a chip row. That was duplicated between them, and
// the duplicate is what silently kept the new-session screen on the old
// photos-only path. It lives here once now; the composers supply only their own
// button styling, which is the part that genuinely differs between the two
// designs.

enum AttachmentSource {
    case photos, files
}

/// Owns everything about the pending attachments for one composer.
@MainActor
@Observable
final class AttachmentTray {
    var items: [ComposerAttachment] = []
    var isLoading = false
    var error: String?

    // Picker presentation. `PhotosPicker` cannot be a `Menu` item — it needs its
    // own presentation — so both pickers are driven by the `isPresented` forms.
    var showPhotoPicker = false
    var showFileImporter = false
    var pickerItems: [PhotosPickerItem] = []

    /// Refuse anything that would take the app — or the single-process host,
    /// which buffers the whole body in memory — down with it. Mirrors the
    /// server's own ceiling so the failure is local, immediate and explainable
    /// rather than a 413 at the end of a long upload.
    nonisolated static let maxAttachmentBytes = 64 * 1024 * 1024

    var isEmpty: Bool { items.isEmpty }

    func choose(_ source: AttachmentSource) {
        switch source {
        case .photos: showPhotoPicker = true
        case .files: showFileImporter = true
        }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items = []
        pickerItems = []
    }

    // MARK: Loading

    /// Photos-library items. These carry no usable original filename — PhotosUI
    /// exposes an identifier, not a name — so the name is generated from the
    /// item's declared content type. The type is the part that matters
    /// downstream anyway: it decides the extension, and the extension decides
    /// whether the agent can read the file at all.
    func load(photos items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoading = true
        defer { isLoading = false; pickerItems = [] }

        var loaded: [ComposerAttachment] = []
        var rejected: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            if let built = Self.makeAttachment(data: data, utType: type, rawName: nil) {
                loaded.append(built)
            } else {
                rejected.append(type?.localizedDescription ?? "That item")
            }
        }
        self.items.append(contentsOf: loaded)
        if !rejected.isEmpty { error = Self.tooLargeMessage(rejected) }
    }

    /// Document-picker URLs. Unlike the photo path these have real names, and
    /// they are security-scoped: reading without claiming the scope fails with a
    /// permission error that looks exactly like a missing file.
    func load(files urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        var loaded: [ComposerAttachment] = []
        var rejected: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)
            if let built = Self.makeAttachment(data: data, utType: type, rawName: url.lastPathComponent) {
                loaded.append(built)
            } else {
                rejected.append(url.lastPathComponent)
            }
        }
        items.append(contentsOf: loaded)
        if !rejected.isEmpty { error = Self.tooLargeMessage(rejected) }
    }

    /// Build the attachment, normalising bytes where the destination demands it.
    /// Returns nil only when the file is over the size ceiling.
    nonisolated static func makeAttachment(
        data: Data,
        utType: UTType?,
        rawName: String?
    ) -> ComposerAttachment? {
        var bytes = data
        var ext = rawName.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
        if ext.isEmpty { ext = utType?.preferredFilenameExtension?.lowercased() ?? "" }

        // HEIC is the iPhone camera default and is NOT a format the model accepts
        // as image input, so it has to be transcoded. Everything else passes
        // through untouched — the previous code re-encoded every photo to PNG,
        // turning a 3 MB HEIC into a 15 MB upload for no benefit at all.
        if ext == "heic" || ext == "heif" {
            if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.9) {
                bytes = jpeg
                ext = "jpg"
            }
        }
        if ext.isEmpty { ext = "dat" }

        guard bytes.count <= maxAttachmentBytes else { return nil }

        let name = rawName.map { ($0 as NSString).deletingPathExtension + "." + ext }
            ?? generatedName(ext: ext)
        let meta = AttachmentMeta(rawFilename: name)
        return ComposerAttachment(data: bytes, meta: meta, preview: preview(for: bytes, meta: meta))
    }

    /// Photos have no name of their own; give them a recognisable one rather
    /// than a bare UUID the user can't connect to what they picked.
    private nonisolated static func generatedName(ext: String) -> String {
        let prefix = AttachmentKind.from(ext: ext) == .video ? "VID" : "IMG"
        return "\(prefix)_\(UUID().uuidString.prefix(6)).\(ext)"
    }

    private nonisolated static func preview(for data: Data, meta: AttachmentMeta) -> UIImage? {
        switch meta.kind {
        case .image: return UIImage(data: data)
        case .video, .file: return nil   // videos get a play badge, files an icon
        }
    }

    private nonisolated static func tooLargeMessage(_ names: [String]) -> String {
        let limit = ByteCountFormatter.string(
            fromByteCount: Int64(maxAttachmentBytes), countStyle: .file)
        return "\(names.joined(separator: ", ")) \(names.count == 1 ? "is" : "are") over the \(limit) attachment limit."
    }
}

// MARK: - Shared UI

/// The two menu entries. Each composer wraps these in its own `Menu` so it keeps
/// the button styling its design calls for.
struct AttachmentMenuItems: View {
    let tray: AttachmentTray

    var body: some View {
        Button { tray.choose(.photos) } label: {
            Label("Photos & Videos", systemImage: "photo.on.rectangle")
        }
        Button { tray.choose(.files) } label: {
            Label("Files", systemImage: "folder")
        }
    }
}

/// Presents both system pickers and the failure alert. Attach once per composer.
struct AttachmentPickers: ViewModifier {
    @Bindable var tray: AttachmentTray

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $tray.showPhotoPicker,
                selection: $tray.pickerItems,
                maxSelectionCount: 6,
                matching: .any(of: [.images, .videos])
            )
            .fileImporter(
                isPresented: $tray.showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): Task { await tray.load(files: urls) }
                case .failure(let error): tray.error = error.localizedDescription
                }
            }
            .onChange(of: tray.pickerItems) { _, items in
                Task { await tray.load(photos: items) }
            }
            .alert(
                "Couldn't attach",
                isPresented: Binding(get: { tray.error != nil }, set: { if !$0 { tray.error = nil } })
            ) {
                Button("OK") { tray.error = nil }
            } message: {
                Text(tray.error ?? "")
            }
    }
}

extension View {
    func attachmentPickers(_ tray: AttachmentTray) -> some View {
        modifier(AttachmentPickers(tray: tray))
    }
}

/// Horizontal row of pending attachments. Visual things show themselves;
/// everything else states what it is — a blank grey square labelled nothing is
/// worse than an icon and a filename.
struct AttachmentChips: View {
    let tray: AttachmentTray

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tray.items) { att in
                    ZStack(alignment: .topTrailing) {
                        chip(att)
                        Button {
                            tray.remove(att.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("Remove \(att.filename)")
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.trailing, 6)   // room for the last chip's ✕ overhang
        }
    }

    @ViewBuilder
    private func chip(_ att: ComposerAttachment) -> some View {
        if let preview = att.preview {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: preview)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if att.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(4)
                }
            }
            .frame(width: 56, height: 56)
            .accessibilityLabel(att.filename)
        } else {
            HStack(spacing: 8) {
                Image(systemName: Self.icon(for: att))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(att.filename)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(att.data.count), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 56)
            .frame(maxWidth: 190)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(att.filename)
        }
    }

    private static func icon(for att: ComposerAttachment) -> String {
        switch (att.filename as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "md", "markdown", "txt", "log": return "doc.text"
        case "csv", "xlsx", "xls": return "tablecells"
        case "json", "xml", "html", "htm": return "curlybraces"
        case "zip": return "doc.zipper"
        case "mp3", "m4a", "wav": return "waveform"
        case "mov", "mp4", "m4v": return "play.rectangle"
        default: return "doc"
        }
    }
}

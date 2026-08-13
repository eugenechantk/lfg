import SwiftUI
import LFGCore

/// Everything a session produced, in one place.
///
/// The transcript renders attachments where they were mentioned, which is right
/// for reading but wrong for retrieval — the chart an agent made two hours and
/// four hundred tool calls ago is somewhere up there, and scrolling is the only
/// way back to it. This is that same parse, flattened: files newest-first, then
/// the web links, each opening exactly what the inline card would have opened.
struct AttachmentsSheet: View {
    let messages: [SessionMessage]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hostFiles) private var hostFiles
    @Environment(\.openURL) private var openURL

    @State private var resources: TranscriptResources?
    @State private var viewing: MediaRef?

    var body: some View {
        NavigationStack {
            Group {
                if let resources {
                    if resources.isEmpty { emptyState } else { list(resources) }
                } else {
                    // Only visible on a very long transcript; the parse is fast.
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Files & Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        // Recompute when the session appends — a live agent adds files while
        // this is open, and a stale list is worse than a slow one.
        .task(id: messages.count) {
            let snapshot = messages
            resources = await Task.detached { TranscriptResourceIndex.collect(from: snapshot) }.value
        }
        .sheet(item: $viewing) { ref in
            FileViewerSheet(ref: ref, url: hostFiles?.resolve(rawPath: ref.raw))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No files yet",
            systemImage: "paperclip",
            description: Text("Files and links this session shares will collect here.")
        )
    }

    private func list(_ resources: TranscriptResources) -> some View {
        List {
            if !resources.files.isEmpty {
                Section("Files") {
                    ForEach(resources.files) { item in
                        Button { viewing = item.ref } label: {
                            row(
                                icon: icon(item.ref.kind),
                                title: item.ref.filename,
                                subtitle: location(item.ref.raw),
                                trailing: relativeTime(item.ts)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !resources.links.isEmpty {
                Section("Links") {
                    ForEach(resources.links) { item in
                        Button {
                            if let url = URL(string: item.link.url) { openURL(url) }
                        } label: {
                            row(
                                icon: "link",
                                title: item.link.displayName,
                                subtitle: item.link.host ?? item.link.url,
                                trailing: relativeTime(item.ts)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(icon: String, title: String, subtitle: String?, trailing: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)   // the tail is the identifying part
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption2).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// Where the file lives — the directory, or the host for a remote URL. Two
    /// files called `chart.png` from different runs are otherwise identical rows.
    private func location(_ raw: String) -> String? {
        if raw.hasPrefix("http"), let host = URL(string: raw)?.host { return host }
        let dir = (raw as NSString).deletingLastPathComponent
        // `./out.png` leaves ".", which is noise dressed up as a location.
        return (dir.isEmpty || dir == ".") ? nil : dir
    }

    private func relativeTime(_ ts: Double?) -> String? {
        guard let ts, ts > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ts / 1000)
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }

    private func icon(_ kind: MediaKind) -> String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .markdown: return "doc.text"
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .other: return "doc"
        }
    }
}

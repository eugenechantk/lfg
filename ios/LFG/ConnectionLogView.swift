import SwiftUI
import LFGCore

/// The connection timeline, on the phone that experienced the drop.
///
/// This screen exists because the "client disconnects on cellular" symptom has
/// outlived three separate code-reading investigations, each of which could only
/// theorise: the failure happens away from any Mac, on a radio no one can
/// observe, and the app kept no record. Being able to hand over a timestamped
/// timeline — captured on the spot, shareable in two taps — is the difference
/// between the next round confirming something and guessing again.
struct ConnectionLogView: View {
    @State private var entries: [ConnectionLogEntry] = []
    @State private var filter: ConnectionLogCategory?
    @State private var shareItem: ConnectionLogExport?
    /// Newest-first, so the drop you just experienced is the first thing on
    /// screen — never make someone scroll to the bottom of 2000 lines to find
    /// the thing that happened ten seconds ago.
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var visible: [ConnectionLogEntry] {
        guard let filter else { return entries }
        return entries.filter { $0.category == filter }
    }

    var body: some View {
        List {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Connection activity is recorded from launch. Come back after a drop.")
                )
                .accessibilityIdentifier("connectionLogEmptyState")
            }
            ForEach(Array(visible.enumerated()), id: \.offset) { _, entry in
                row(entry)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Connection Log")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { categoryFilter }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareItem = ConnectionLogExport(text: ConnectionLog.shared.exportText())
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityIdentifier("connectionLogShareButton")
                .accessibilityLabel("Share connection log")
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.text])
        }
        .task {
            // Poll rather than observe: the log is written from the network
            // queue and several actors, and a 1s refresh is far cheaper than
            // making every write hop to the main actor just to update a screen
            // that is open for a minute a month.
            while !Task.isCancelled {
                entries = ConnectionLog.shared.recentEntries()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .accessibilityIdentifier("connectionLogView")
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "All", active: filter == nil) { filter = nil }
                ForEach(ConnectionLogCategory.allCases, id: \.self) { c in
                    chip(title: c.rawValue, active: filter == c) {
                        filter = (filter == c) ? nil : c
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: Capsule())
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("connectionLogFilter_\(title)")
    }

    private func row(_ entry: ConnectionLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(stamp.string(from: entry.at))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(entry.category.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint(entry.category))
                if let host = entry.host {
                    Text(host).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(entry.message)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
    }

    private func tint(_ c: ConnectionLogCategory) -> Color {
        switch c {
        case .path: return .purple
        case .state: return .orange
        case .link: return .blue
        case .stream: return .green
        case .probe: return .teal
        case .keepalive: return .gray
        case .lifecycle: return .pink
        case .send: return .indigo
        }
    }
}

/// Identifiable wrapper so the share sheet can be driven by `.sheet(item:)` —
/// the text is snapshotted at tap time, not re-read while the sheet is up.
private struct ConnectionLogExport: Identifiable {
    let id = UUID()
    let text: String
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

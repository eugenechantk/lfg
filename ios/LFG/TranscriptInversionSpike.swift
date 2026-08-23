import SwiftUI
import LFGCore

/// PHASE-2 SPIKE — not production. Reached from the ••• menu.
///
/// The whole point is what is ABSENT. There is no scroll pin, no follow loop, no
/// `.scrollPosition(id:)` binding, no anchor, no `windowStart` arithmetic, no
/// geometry observation. If the two product constraints hold anyway, they are
/// structural rather than maintained — which is the claim the inverted-list
/// architecture makes.
///
/// How it works: the stack is flipped 180° and so is every row, so the array's
/// FIRST element renders at the visual BOTTOM.
///
/// - "Open shows the latest message" becomes `contentOffset == 0`, the scroll
///   view's natural resting state.
/// - "Older pages attach at the top" becomes appending to the END of the array,
///   which grows content at offsets the reader is not looking at — so the
///   viewport cannot be displaced by it.
struct InvertedTranscriptSpike: View {
    let sessionID: String
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Newest-N prefix. Note this is a *prefix*, not a count-from-the-end —
    /// `TranscriptWindow.startIndex` and every bug that came from it disappear.
    @State private var window = 25   // SPIKE: small so reveals are reachable
    @State private var revealCount = 0

    private var messages: [SessionMessage] { store.transcripts[sessionID] ?? [] }
    private var rows: [SessionMessage] {
        Array(messages.reversed().prefix(window))
    }
    private var hasOlder: Bool { window < messages.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows, id: \.stableID) { message in
                        TranscriptMessageView(message: message)
                            .flippedRow()
                            .id(message.stableID)
                    }

                    // Visually the TOP of the transcript. Structurally the end
                    // of the array — appending here is what makes a history
                    // reveal free.
                    if hasOlder {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.mini)
                            Text("Earlier messages").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .flippedRow()
                        .accessibilityIdentifier("spikeOlderLoader")
                        .onAppear {
                            revealCount += 1
                            window = min(messages.count, window + 25)
                        }
                    }
                }
                .padding()
            }
            .flippedRow()
            .scrollIndicators(.hidden)
            .navigationTitle("Spike · inverted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("inverted · \(rows.count)/\(messages.count) · reveals \(revealCount)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("spikeStatus")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("spikeDoneButton")
                }
                // SPIKE: append a page with NO gesture, so prepend stability can
                // be measured without a scroll confounding it.
                ToolbarItem(placement: .cancellationAction) {
                    Button("+page") {
                        revealCount += 1
                        window = min(messages.count, window + 25)
                    }
                    .accessibilityIdentifier("spikeRevealButton")
                }
            }
        }
    }
}

private extension View {
    /// The 180° flip. Applied to the container AND to each row, so rows read
    /// the right way up inside an upside-down stack.
    func flippedRow() -> some View {
        scaleEffect(x: 1, y: -1, anchor: .center)
    }
}

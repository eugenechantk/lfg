import SwiftUI
import LFGCore
import UIKit

/// App-owned floating preview of the most recent browser automation action.
/// This is intentionally not labelled "Live": frames arrive after meaningful
/// browser action batches, so the timestamp describes the real freshness.
struct BrowserPreviewCard: View {
    let frame: BrowserFrame
    let image: UIImage?
    let imageLoadFailed: Bool
    let size: CGSize
    let onOpenFullscreen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "safari")
                    .font(.caption.weight(.semibold))
                Text("Browser Preview")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ageLabel(at: context.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close browser preview")
                .accessibilityIdentifier("browser_preview_close_button")
            }
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .frame(height: 32)

            Button(action: onOpenFullscreen) {
                BrowserPreviewImage(image: image, loadFailed: imageLoadFailed)
                    .frame(width: size.width, height: size.height - 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open browser preview full screen")
            .accessibilityIdentifier("browser_preview_content_button")
            .background(Color(.secondarySystemBackground))
            .clipped()
        }
        .frame(width: size.width)
        .glassOrRaised(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private func ageLabel(at now: Date) -> String {
        let captured = Date(timeIntervalSince1970: frame.capturedAt / 1_000)
        let seconds = max(0, Int(now.timeIntervalSince(captured)))
        if seconds < 2 { return "Now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        return "Updated \(seconds / 60)m ago"
    }
}

struct BrowserPreviewOverlay: View {
    let frame: BrowserFrame
    let url: URL
    let onDismiss: () -> Void

    @State private var restingCenter: CGPoint?
    @State private var dockedEdge: BrowserPreviewDockEdge?
    @State private var isFullscreen = false
    @State private var previewImage: UIImage?
    @State private var imageLoadFailed = false
    @GestureState private var dragTranslation = CGSize.zero

    private var cardSize: CGSize {
        guard let previewImage, previewImage.size.height > 0 else {
            return CGSize(width: 190, height: 144)
        }

        let aspectRatio = previewImage.size.width / previewImage.size.height
        let imageSize: CGSize
        if aspectRatio >= 1 {
            let width: CGFloat = 220
            imageSize = CGSize(
                width: width,
                height: min(max(width / aspectRatio, 96), 220)
            )
        } else {
            let height: CGFloat = 220
            imageSize = CGSize(
                width: min(max(height * aspectRatio, 190), 220),
                height: height
            )
        }
        return CGSize(width: imageSize.width, height: imageSize.height + 32)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(in: proxy.size)

            ZStack {
                if let dockedEdge {
                    dockHandle(edge: dockedEdge, layout: layout, size: proxy.size)
                        .transition(.move(edge: dockedEdge.swiftUIEdge).combined(with: .opacity))
                } else {
                    let center = resolvedCenter(layout: layout)
                    let draggedCenter = layout.constrained(
                        BrowserPreviewPoint(
                            x: Double(center.x + dragTranslation.width),
                            y: Double(center.y + dragTranslation.height)
                        )
                    )

                    BrowserPreviewCard(
                        frame: frame,
                        image: previewImage,
                        imageLoadFailed: imageLoadFailed,
                        size: cardSize,
                        onOpenFullscreen: { isFullscreen = true },
                        onDismiss: onDismiss
                    )
                    .position(x: draggedCenter.x, y: draggedCenter.y)
                    // The card owns drags that begin on it. In a navigation stack,
                    // a rightward drag otherwise competes with interactive-pop.
                    .highPriorityGesture(dragGesture(layout: layout))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.28), value: dockedEdge)
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            BrowserPreviewFullscreen(
                image: previewImage,
                imageLoadFailed: imageLoadFailed
            ) {
                isFullscreen = false
            }
        }
        .task(id: frame.frameId) {
            await loadPreviewImage()
        }
    }

    private func makeLayout(in size: CGSize) -> BrowserPreviewLayout {
        BrowserPreviewLayout(
            containerWidth: Double(size.width),
            containerHeight: Double(size.height),
            previewWidth: Double(cardSize.width),
            previewHeight: Double(cardSize.height)
        )
    }

    private func resolvedCenter(layout: BrowserPreviewLayout) -> CGPoint {
        let initial = restingCenter ?? CGPoint(
            x: layout.trailingCenterX,
            y: 10 + cardSize.height / 2
        )
        let constrained = layout.constrained(
            BrowserPreviewPoint(x: Double(initial.x), y: Double(initial.y))
        )
        return CGPoint(x: constrained.x, y: constrained.y)
    }

    private func dragGesture(layout: BrowserPreviewLayout) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let start = resolvedCenter(layout: layout)
                let proposed = BrowserPreviewPoint(
                    x: Double(start.x + value.translation.width),
                    y: Double(start.y + value.translation.height)
                )

                if let edge = layout.dockEdge(forUnconstrainedX: proposed.x) {
                    restingCenter = CGPoint(
                        x: edge == .leading ? layout.leadingCenterX : layout.trailingCenterX,
                        y: layout.constrained(proposed).y
                    )
                    dockedEdge = edge
                } else {
                    let constrained = layout.constrained(proposed)
                    restingCenter = CGPoint(x: constrained.x, y: constrained.y)
                }
            }
    }

    private func dockHandle(
        edge: BrowserPreviewDockEdge,
        layout: BrowserPreviewLayout,
        size: CGSize
    ) -> some View {
        let restingY = resolvedCenter(layout: layout).y
        let y = min(max(restingY, 54), size.height - 54)

        return Button {
            restingCenter = CGPoint(
                x: edge == .leading ? layout.leadingCenterX : layout.trailingCenterX,
                y: y
            )
            dockedEdge = nil
        } label: {
            VStack(spacing: 7) {
                Image(systemName: "safari")
                    .font(.caption.weight(.semibold))
                Image(systemName: edge == .leading ? "chevron.right" : "chevron.left")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.primary)
            .frame(width: 36, height: 82)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassOrRaised(
            in: UnevenRoundedRectangle(
                topLeadingRadius: edge == .leading ? 0 : 14,
                bottomLeadingRadius: edge == .leading ? 0 : 14,
                bottomTrailingRadius: edge == .trailing ? 0 : 14,
                topTrailingRadius: edge == .trailing ? 0 : 14
            ),
            interactive: true
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .accessibilityLabel("Restore browser preview")
        .accessibilityIdentifier("browser_preview_docked_handle")
        .position(x: edge == .leading ? 18 : size.width - 18, y: y)
    }

    private func loadPreviewImage() async {
        imageLoadFailed = false
        do {
            let data: Data
            if let client = HostCredentialStore.shared.client(forResourceURL: url) {
                data = try await client.resourceData(from: url)
            } else {
                data = try await URLSession.shared.data(from: url).0
            }
            guard !Task.isCancelled, let image = UIImage(data: data) else {
                if !Task.isCancelled { imageLoadFailed = true }
                return
            }
            previewImage = image
        } catch is CancellationError {
            return
        } catch {
            imageLoadFailed = true
        }
    }
}

private struct BrowserPreviewImage: View {
    let image: UIImage?
    let loadFailed: Bool

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    // Browser windows can be portrait, landscape, or split.
                    // Preserve the whole observed viewport; cropping can hide
                    // the exact control the agent just manipulated.
                    .scaledToFit()
                    .transition(.opacity)
            } else if loadFailed {
                ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
            } else {
                ProgressView()
            }
        }
    }
}

private struct BrowserPreviewFullscreen: View {
    let image: UIImage?
    let imageLoadFailed: Bool
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            BrowserPreviewImage(image: image, loadFailed: imageLoadFailed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)

            VStack {
                HStack(spacing: 10) {
                    Image(systemName: "safari")
                    Text("Browser Preview")
                        .font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close full screen browser preview")
                    .accessibilityIdentifier("browser_preview_fullscreen_close_button")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}

private extension BrowserPreviewDockEdge {
    var swiftUIEdge: Edge {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

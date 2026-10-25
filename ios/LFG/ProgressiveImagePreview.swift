import Foundation
import Observation
import UIKit

/// Owns one image's preview-to-original load. UIKit decoding/preparation happens
/// off the main actor; only publishing the prepared image touches view state.
@MainActor @Observable
final class ProgressiveImagePreview {
    private(set) var image: UIImage?
    private(set) var isOriginal = false
    private(set) var isLoadingOriginal = false
    private(set) var error: String?
    private var loadID = UUID()

    func load(previewURL: URL, originalURL: URL,
              fetch: @Sendable (URL) async throws -> Data) async {
        let id = UUID()
        loadID = id
        image = nil
        isOriginal = false
        error = nil
        isLoadingOriginal = false
        defer { if loadID == id { isLoadingOriginal = false } }

        if previewURL != originalURL {
            do {
                let preview = try await Self.decode(fetch(previewURL))
                try Task.checkCancellation()
                guard loadID == id else { return }
                image = preview
            } catch {
                guard !Task.isCancelled, loadID == id else { return }
                // A missing/invalid rendition must not prevent the original.
            }
        }

        guard !Task.isCancelled, loadID == id else { return }
        isLoadingOriginal = true
        do {
            let original = try await Self.decode(fetch(originalURL))
            try Task.checkCancellation()
            guard loadID == id else { return }
            image = original
            isOriginal = true
        } catch {
            guard !Task.isCancelled, loadID == id else { return }
            // Keep an already visible preview usable after a network failure.
            if image == nil { self.error = error.localizedDescription }
        }
    }

    nonisolated private static func decode(_ data: Data) async throws -> UIImage {
        let image = await Task.detached(priority: .utility) {
            guard let image = UIImage(data: data) else { return nil as UIImage? }
            return await image.byPreparingForDisplay() ?? image
        }.value
        try Task.checkCancellation()
        guard let image else { throw URLError(.cannotDecodeContentData) }
        return image
    }
}

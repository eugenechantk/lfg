import Testing
import UIKit
import LFGCore
@testable import LFG

@Suite @MainActor
struct ProgressiveImagePreviewTests {
    private func png(_ size: CGSize, color: UIColor = .blue) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func previewAppearsWhileOriginalIsStillLoading() async {
        let source = ImageFetchGate(preview: png(CGSize(width: 30, height: 100)),
                                   original: png(CGSize(width: 300, height: 1000)))
        let model = ProgressiveImagePreview()
        let task = Task { await model.load(previewURL: source.previewURL, originalURL: source.originalURL,
                                           fetch: { try await source.fetch($0) }) }
        await source.waitForOriginal()
        #expect(model.image?.size == CGSize(width: 30, height: 100))
        #expect(model.isLoadingOriginal)
        #expect(!model.isOriginal)
        await source.release()
        await task.value
        #expect(model.image?.size == CGSize(width: 300, height: 1000))
        #expect(model.isOriginal)
        #expect(!model.isLoadingOriginal)
        #expect(await source.requestedURLs == [source.previewURL, source.originalURL])
        #expect(!URLComponents(url: source.originalURL, resolvingAgainstBaseURL: false)!.queryItems!.contains { $0.name == "w" })
    }

    @Test func failedPreviewStillLoadsOriginal() async {
        let source = ImageFetchGate(preview: nil, original: png(CGSize(width: 300, height: 1000)))
        await source.release()
        let model = ProgressiveImagePreview()
        await model.load(previewURL: source.previewURL, originalURL: source.originalURL,
                         fetch: { try await source.fetch($0) })
        #expect(model.isOriginal)
        #expect(model.error == nil)
    }

    @Test func failedOriginalRetainsUsablePreview() async {
        let source = ImageFetchGate(preview: png(CGSize(width: 30, height: 100)), original: nil)
        await source.release()
        let model = ProgressiveImagePreview()
        await model.load(previewURL: source.previewURL, originalURL: source.originalURL,
                         fetch: { try await source.fetch($0) })
        #expect(model.image?.size == CGSize(width: 30, height: 100))
        #expect(!model.isOriginal)
        #expect(!model.isLoadingOriginal)
        #expect(model.error == nil)
    }

    @Test func invalidImagesFailWithoutReplacingPreview() async {
        let source = ImageFetchGate(preview: png(CGSize(width: 30, height: 100)), original: Data("invalid".utf8))
        await source.release()
        let model = ProgressiveImagePreview()
        await model.load(previewURL: source.previewURL, originalURL: source.originalURL,
                         fetch: { try await source.fetch($0) })
        #expect(model.image?.size == CGSize(width: 30, height: 100))
        #expect(!model.isOriginal)
    }

    @Test func bothRequestsFailShowsError() async {
        let source = ImageFetchGate(preview: nil, original: nil)
        await source.release()
        let model = ProgressiveImagePreview()
        await model.load(previewURL: source.previewURL, originalURL: source.originalURL,
                         fetch: { try await source.fetch($0) })
        #expect(model.image == nil)
        #expect(model.error != nil)
    }

    @Test func cancelledOriginalCannotPublishLateResponse() async {
        let source = ImageFetchGate(preview: png(CGSize(width: 30, height: 100)),
                                   original: png(CGSize(width: 300, height: 1000)))
        let model = ProgressiveImagePreview()
        let task = Task { await model.load(previewURL: source.previewURL, originalURL: source.originalURL,
                                           fetch: { try await source.fetch($0) }) }
        await source.waitForOriginal()
        task.cancel()
        await source.release()
        await task.value
        #expect(!model.isOriginal)
        #expect(model.image?.size == CGSize(width: 30, height: 100))
    }

    @Test func externalOriginalIsNotFetchedTwice() async {
        let source = ImageFetchGate(preview: nil, original: png(CGSize(width: 30, height: 100)))
        await source.release()
        let model = ProgressiveImagePreview()
        await model.load(previewURL: source.originalURL, originalURL: source.originalURL,
                         fetch: { try await source.fetch($0) })
        #expect(model.isOriginal)
        #expect(await source.requestedURLs == [source.originalURL])
    }

    @Test func viewerRequestsRenditionThenUnsizedAuthenticatedHostURL() {
        let host = HostFiles(client: LFGClient(baseURL: URL(string: "https://lfg.invalid")!))
        let ref = MediaRef(raw: "/Users/eugene/canvas.png", kind: .image)
        let preview = URLComponents(url: host.viewerURL(for: ref)!, resolvingAgainstBaseURL: false)!
        let original = URLComponents(url: host.shareURL(for: ref)!, resolvingAgainstBaseURL: false)!
        #expect(preview.queryItems?.first { $0.name == "w" }?.value == "2400")
        #expect(original.queryItems?.contains { $0.name == "w" } == false)
        #expect(original.queryItems?.first { $0.name == "path" }?.value == ref.raw)
    }

    @Test func replacingPixelsPreservesViewportAndEnablesSourceDetail() {
        let preview = UIImage(data: png(CGSize(width: 100, height: 330)))!
        let original = UIImage(data: png(CGSize(width: 1000, height: 3300)))!
        let scroll = ZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 180))
        let imageView = UIImageView(image: preview)
        imageView.contentMode = .scaleAspectFit
        scroll.imageView = imageView
        scroll.addSubview(imageView)
        let coordinator = ZoomableImageView.Coordinator(onZoomChanged: { _ in })
        scroll.delegate = coordinator
        coordinator.scrollView = scroll
        scroll.layoutIfNeeded()
        scroll.setZoomScale(2, animated: false)
        scroll.contentOffset = CGPoint(x: 50, y: 200)
        let offset = scroll.contentOffset
        let zoom = scroll.zoomScale
        let frame = imageView.frame
        scroll.replaceImage(original, isOriginal: true)
        scroll.layoutIfNeeded()
        #expect(scroll.zoomScale == zoom)
        #expect(scroll.contentOffset == offset)
        #expect(imageView.frame == frame)
        #expect(scroll.maximumZoomScale >= 10)
        #expect(imageView.image === original)
        #expect(imageView.accessibilityValue == "Full resolution, 1000 by 3300 pixels")
    }
}

private actor ImageFetchGate {
    nonisolated let previewURL = URL(string: "https://fixture.invalid/api/file?path=canvas.png&w=2400")!
    nonisolated let originalURL = URL(string: "https://fixture.invalid/api/file?path=canvas.png")!
    let preview: Data?
    let original: Data?
    var requestedURLs: [URL] = []
    private var started = false
    private var released = false
    private var waitingForStart: CheckedContinuation<Void, Never>?
    private var waitingForRelease: CheckedContinuation<Void, Never>?

    init(preview: Data?, original: Data?) { self.preview = preview; self.original = original }
    func fetch(_ url: URL) async throws -> Data {
        requestedURLs.append(url)
        if url == previewURL {
            guard let preview else { throw URLError(.cannotLoadFromNetwork) }
            return preview
        }
        started = true
        waitingForStart?.resume(); waitingForStart = nil
        if !released { await withCheckedContinuation { waitingForRelease = $0 } }
        guard let original else { throw URLError(.cannotLoadFromNetwork) }
        return original
    }
    func waitForOriginal() async {
        if !started { await withCheckedContinuation { waitingForStart = $0 } }
    }
    func release() {
        released = true
        waitingForRelease?.resume(); waitingForRelease = nil
    }
}

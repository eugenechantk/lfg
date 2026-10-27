#if os(iOS)
import SwiftUI
import AVFoundation
import LFGCore

/// UIKit owns zoom and touch conversion, so gestures always arrive in the
/// guest image's local coordinates, including after zoom, pan and rotation.
final class SpaceDesktopScrollView: UIScrollView, UIScrollViewDelegate {
    let desktop = SpaceInputSurface()
    var aspect: CGFloat = 1.6 { didSet { if aspect != oldValue { setNeedsLayout() } } }
    private var viewport = CGSize.zero
    private var fitted = CGSize.zero
    var fitToken = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never; keyboardDismissMode = .none
        panGestureRecognizer.minimumNumberOfTouches = 2
        addSubview(desktop)
        accessibilityIdentifier = "message_control_viewport"
        isAccessibilityElement = false
        for tap in desktop.gestureRecognizers?.compactMap({ $0 as? UITapGestureRecognizer }) ?? [] {
            tap.require(toFail: panGestureRecognizer)
            if let pinchGestureRecognizer { tap.require(toFail: pinchGestureRecognizer) }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let next = SpaceViewport.fittedSize(in: bounds.size, aspect: aspect)
        guard bounds.size != viewport || next != fitted else { return }
        let center = desktop.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self)
        let normalized = fitted == .zero ? CGPoint(x: 0.5, y: 0.5) : SpaceViewport.normalized(center, in: fitted)
        let scale = zoomScale
        viewport = bounds.size; fitted = next
        setZoomScale(1, animated: false)
        desktop.frame = CGRect(origin: .zero, size: next); contentSize = next
        setZoomScale(scale, animated: false)
        centerContent()
        let x = normalized.x * next.width * scale - bounds.width / 2
        let y = normalized.y * next.height * scale - bounds.height / 2
        contentOffset = CGPoint(x: min(max(-contentInset.left, x), max(-contentInset.left, contentSize.width-bounds.width+contentInset.right)),
                                y: min(max(-contentInset.top, y), max(-contentInset.top, contentSize.height-bounds.height+contentInset.bottom)))
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { desktop }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }
    private func centerContent() {
        contentInset = UIEdgeInsets(top: max(0, (bounds.height-contentSize.height)/2), left: max(0, (bounds.width-contentSize.width)/2), bottom: 0, right: 0)
        accessibilityValue = "Zoom \(Int(zoomScale * 100)) percent"
    }
    func fit() { setZoomScale(1, animated: false); centerContent(); contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top) }
}

struct SpaceZoomCanvas: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let aspect: CGFloat
    let active: Bool
    let keyboard: Bool
    let fitToken: Int
    let send: SpaceInput
    func makeUIView(context: Context) -> SpaceDesktopScrollView {
        let view = SpaceDesktopScrollView()
        view.desktop.video = layer; view.desktop.layer.addSublayer(layer)
        return view
    }
    func updateUIView(_ view: SpaceDesktopScrollView, context: Context) {
        view.aspect = aspect
        view.desktop.configure(active: active, keyboard: keyboard, send: send)
        if view.fitToken != fitToken { view.fitToken = fitToken; view.fit() }
    }
    static func dismantleUIView(_ view: SpaceDesktopScrollView, coordinator: ()) {
        view.desktop.configure(active: false, keyboard: false, send: { _, _ in })
        view.desktop.video?.removeFromSuperlayer()
    }
}
#endif

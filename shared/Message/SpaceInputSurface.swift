import SwiftUI
import AVFoundation
#if canImport(LFGCore)
import LFGCore
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

typealias SpaceInput = (String, [String: String]) -> Void

private func pointValues(_ point: CGPoint, _ size: CGSize) -> [String: String] {
    #if os(iOS)
    let normalized = SpaceViewport.normalized(point, in: size)
    return ["x": String(Double(normalized.x)), "y": String(Double(normalized.y))]
    #else
    return ["x": String(Double(min(1, max(0, point.x / max(1, size.width))))),
     "y": String(Double(min(1, max(0, point.y / max(1, size.height)))))]
    #endif
}

#if os(macOS)
final class SpaceInputSurface: NSView {
    var video: AVSampleBufferDisplayLayer?
    var active = false
    var send: SpaceInput = { _, _ in }
    private var start: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { active }
    override func layout() { super.layout(); video?.frame = bounds }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    override func mouseMoved(with event: NSEvent) { if active { send("move", pointValues(point(event), bounds.size)) } }
    override func mouseDown(with event: NSEvent) {
        guard active else { return }; window?.makeFirstResponder(self); start = point(event)
    }
    override func mouseUp(with event: NSEvent) {
        guard active, let origin = start else { return }; start = nil
        let end = point(event); var values = pointValues(end, bounds.size)
        if hypot(end.x-origin.x, end.y-origin.y) > 4 {
            let from = pointValues(origin, bounds.size); values["fromX"] = from["x"]; values["fromY"] = from["y"]
            values["live"] = "true"; send("drag", values)
        } else { values["live"] = "true"; send("click", values) }
    }
    override func rightMouseDown(with event: NSEvent) { if active { var values = pointValues(point(event), bounds.size); values["live"] = "true"; send("rightClick", values) } }
    override func scrollWheel(with event: NSEvent) { if active && abs(event.scrollingDeltaY) > 0 { send("scroll", ["direction": event.scrollingDeltaY > 0 ? "up" : "down"]) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if active && window?.firstResponder === self && !event.modifierFlags.intersection([.command, .control]).isEmpty {
            keyDown(with: event); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        guard active else { return }
        let names: [UInt16: String] = [36:"enter",48:"tab",51:"backspace",53:"escape",115:"home",116:"pageup",117:"delete",119:"end",121:"pagedown",123:"left",124:"right",125:"down",126:"up"]
        var modifiers: [String] = []
        // macOS Command maps to the Linux application's Control shortcuts.
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { modifiers.append("ctrl") }
        if event.modifierFlags.contains(.option) { modifiers.append("alt") }
        if let name = names[event.keyCode] {
            if event.modifierFlags.contains(.shift) { modifiers.append("shift") }
            send("key", ["key": (modifiers + [name]).joined(separator: "+")])
        } else if !modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 {
            if event.modifierFlags.contains(.shift) { modifiers.append("shift") }
            send("key", ["key": (modifiers + [key == " " ? "space" : key]).joined(separator: "+")])
        } else { interpretKeyEvents([event]) }
    }
    override func insertText(_ insertString: Any) {
        if let text = insertString as? String, active { send("type", ["text": text]) }
    }
}
struct SpaceInputCanvas: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let active: Bool
    let keyboard: Bool
    let send: SpaceInput
    func makeNSView(context: Context) -> SpaceInputSurface {
        let view = SpaceInputSurface(); view.wantsLayer = true; view.video = layer; view.layer?.addSublayer(layer); return view
    }
    func updateNSView(_ view: SpaceInputSurface, context: Context) {
        view.active = active; view.send = send; layer.frame = view.bounds
        if !active && view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
    }
}
#else
private final class SpaceKeyboardInput: UITextView, UITextViewDelegate {
    var active = false
    var send: SpaceInput = { _, _ in }
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self; text = " "; selectedRange = NSRange(location: 1, length: 0)
        autocorrectionType = .no; autocapitalizationType = .none
        spellCheckingType = .no; smartQuotesType = .no; smartDashesType = .no
        inputAssistantItem.leadingBarButtonGroups = []; inputAssistantItem.trailingBarButtonGroups = []
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard active else { return false }
        if text.isEmpty && range.length > 0 { send("key", ["key":"backspace"]) }
        else if text == "\n" { send("key", ["key":"enter"]) }
        else if !text.isEmpty { send("type", ["text":text]) }
        return false
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard active else { return super.pressesBegan(presses, with: event) }
        let names: [UIKeyboardHIDUsage: String] = [.keyboardEscape:"escape",.keyboardTab:"tab",.keyboardUpArrow:"up",.keyboardDownArrow:"down",.keyboardLeftArrow:"left",.keyboardRightArrow:"right",.keyboardDeleteForward:"delete",.keyboardHome:"home",.keyboardEnd:"end",.keyboardPageUp:"pageup",.keyboardPageDown:"pagedown"]
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key else { unhandled.insert(press); continue }
            var modifiers: [String] = []
            if key.modifierFlags.contains(.command) || key.modifierFlags.contains(.control) { modifiers.append("ctrl") }
            if key.modifierFlags.contains(.alternate) { modifiers.append("alt") }
            if let name = names[key.keyCode] {
                if key.modifierFlags.contains(.shift) { modifiers.append("shift") }
                send("key", ["key": (modifiers + [name]).joined(separator: "+")])
            } else if !modifiers.isEmpty, key.charactersIgnoringModifiers.count == 1 {
                if key.modifierFlags.contains(.shift) { modifiers.append("shift") }
                send("key", ["key": (modifiers + [key.charactersIgnoringModifiers.lowercased()]).joined(separator: "+")])
            } else { unhandled.insert(press) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
}
final class SpaceInputSurface: UIView {
    var video: AVSampleBufferDisplayLayer?
    var active = false
    var send: SpaceInput = { _, _ in }
    fileprivate let keyboardInput = SpaceKeyboardInput(frame: .zero, textContainer: nil)
    var wantsKeyboard = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        keyboardInput.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        keyboardInput.alpha = 0.01
        addSubview(keyboardInput)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        let rightTap = UITapGestureRecognizer(target: self, action: #selector(rightTap(_:)))
        rightTap.numberOfTouchesRequired = 2
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(tap); addGestureRecognizer(rightTap); addGestureRecognizer(pan)
        tap.require(toFail: pan); tap.require(toFail: rightTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); video?.frame = bounds }
    func configure(active: Bool, keyboard: Bool, send: @escaping SpaceInput) {
        self.active = active; self.send = send
        gestureRecognizers?.forEach { $0.isEnabled = active }
        wantsKeyboard = active && keyboard
        keyboardInput.active = active; keyboardInput.send = send
        if wantsKeyboard {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wantsKeyboard, self.window != nil else { return }
                if !self.keyboardInput.isFirstResponder { self.keyboardInput.becomeFirstResponder() }
            }
        } else if keyboardInput.isFirstResponder { keyboardInput.resignFirstResponder() }
    }
    @objc func rightTap(_ gesture: UITapGestureRecognizer) {
        guard active else { return }
        var values = pointValues(gesture.location(in: self), bounds.size)
        values["live"] = "true"; send("rightClick", values)
    }
    @objc func tap(_ gesture: UITapGestureRecognizer) {
        guard active else { return }; var values = pointValues(gesture.location(in: self), bounds.size); values["live"] = "true"; send("click", values)
    }
    @objc func pan(_ gesture: UIPanGestureRecognizer) {
        guard active, gesture.state == .ended else { return }
        let end = gesture.location(in: self), delta = gesture.translation(in: self)
        var values = pointValues(end, bounds.size)
        let from = pointValues(CGPoint(x: end.x-delta.x, y: end.y-delta.y), bounds.size)
        values["fromX"] = from["x"]; values["fromY"] = from["y"]; values["live"] = "true"; send("drag", values)
    }

}
struct SpaceInputCanvas: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let active: Bool
    let keyboard: Bool
    let send: SpaceInput
    func makeUIView(context: Context) -> SpaceInputSurface {
        let view = SpaceInputSurface(); view.video = layer; view.layer.addSublayer(layer)
        return view
    }
    func updateUIView(_ view: SpaceInputSurface, context: Context) {
        layer.frame = view.bounds
        view.configure(active: active, keyboard: keyboard, send: send)
    }
}
#endif

import AppKit
import ScreenCaptureKit
import CoreImage
import ApplicationServices

// Only stdout carries protocol messages. Never print input, titles, or frames to logs.
final class Wire {
    private let lock = NSLock()
    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        lock.lock(); defer { lock.unlock() }
        do { try FileHandle.standardOutput.write(contentsOf: data + Data([10])) } catch { Darwin.exit(0) }
    }
}
let wire = Wire()

// CGSessionCopyCurrentDictionary is public. The lock-state key is supplied by
// WindowServer (also used by established macOS input tools); unknown/no-console
// sessions are refused. Recheck before every input so secrets never hit loginwindow.
func desktopAllowsInput() -> Bool {
    guard let properties = CGSessionCopyCurrentDictionary() as? [String: Any],
          properties[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
    return properties["CGSSessionScreenIsLocked"] as? Bool != true
        && CGDisplayIsAsleep(CGMainDisplayID()) == 0
}

func windowBounds(_ id: CGWindowID) -> CGRect? {
    guard let rows = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
          let row = rows.first,
          let raw = row[kCGWindowBounds as String] as? [String: Any],
          (row[kCGWindowIsOnscreen as String] as? Bool) == true else { return nil }
    return CGRect(dictionaryRepresentation: raw as CFDictionary)
}

final class CaptureOutput: NSObject, SCStreamOutput {
    let windowID: CGWindowID
    let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var ready = true
    private var stopped = false
    private var geometry = 0
    private var bounds: CGRect?
    init(windowID: CGWindowID, generation: Int) { self.windowID = windowID; geometry = generation }
    func acknowledge(_ id: Int) { lock.lock(); if id == geometry { ready = true }; lock.unlock() }
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    func current(_ id: Int) -> CGRect? {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, id == geometry else { return nil }
        return bounds
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer,
              let rect = windowBounds(windowID) else { return }
        lock.lock()
        guard ready, !stopped else { lock.unlock(); return }
        ready = false
        if bounds != rect { geometry += 1; bounds = rect }
        let id = geometry
        lock.unlock()
        let image = CIImage(cvPixelBuffer: buffer)
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.65]), data.count < 2_000_000 else {
            acknowledge(id); return
        }
        wire.send(["type":"frame", "windowId":windowID, "frameId":id, "width":CVPixelBufferGetWidth(buffer),
                   "height":CVPixelBufferGetHeight(buffer), "jpeg":data.base64EncodedString()])
    }
}

@MainActor final class StreamHost: NSObject, SCStreamDelegate {
    var stream: SCStream?
    var output: CaptureOutput?
    var windows: [SCWindow] = []
    var selected: SCWindow?
    var controlling = false
    var generation = 0
    var heldButton: CGMouseButton?
    var pointer = CGPoint.zero
    var lastSequence = 0

    func error(_ message: String) { wire.send(["type":"error", "message":message]) }
    func stopControl() {
        if let button = heldButton {
            CGEvent(mouseEventSource: nil, mouseType: button == .left ? .leftMouseUp : .rightMouseUp,
                    mouseCursorPosition: pointer, mouseButton: button)?.post(tap: .cghidEventTap)
        }
        heldButton = nil; controlling = false
        wire.send(["type":"control", "enabled":false])
    }
    func list() async {
        guard CGPreflightScreenCaptureAccess() else {
            error("On the Mac, open LFG Browser Stream and grant Screen Recording in System Settings, then reconnect.")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            windows = content.windows.filter { $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 80 && $0.owningApplication?.processID != getpid() }
            windows.sort { a,b in
                let ac = a.owningApplication?.bundleIdentifier.contains("Chrome") == true
                let bc = b.owningApplication?.bundleIdentifier.contains("Chrome") == true
                return ac != bc ? ac : (a.owningApplication?.applicationName ?? "") < (b.owningApplication?.applicationName ?? "")
            }
            wire.send(["type":"windows", "accessibility":AXIsProcessTrusted(), "windows":windows.map {
                ["id":$0.windowID,"title":$0.title ?? "Untitled window", "app":$0.owningApplication?.applicationName ?? "App"] as [String:Any]
            }])
        } catch { self.error("Unable to list windows. Check Screen Recording permission and that the Mac is unlocked.") }
    }
    func select(_ id: Int) async {
        stopControl(); output?.stop()
        if let stream { try? await stream.stopCapture() }
        self.stream = nil; output = nil; selected = nil
        guard let window = windows.first(where: { $0.windowID == id }), windowBounds(window.windowID) != nil else {
            error("That window is no longer available. Reconnect to refresh windows."); return
        }
        do {
            generation += 100000
            let output = CaptureOutput(windowID: window.windowID, generation: generation)
            let config = SCStreamConfiguration()
            let ratio = min(1.0, 1440.0 / window.frame.width)
            config.width = Int(window.frame.width * ratio) / 2 * 2
            config.height = Int(window.frame.height * ratio) / 2 * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            config.queueDepth = 3; config.showsCursor = true
            config.capturesAudio = false
            config.ignoreShadowsSingleWindow = true
            config.shouldBeOpaque = true
            let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: self)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label:"lfg.capture",qos:.userInteractive))
            self.output = output; self.stream = stream; selected = window
            try await stream.startCapture()
            wire.send(["type":"selected","windowId":id])
        } catch { self.error("Unable to capture this window. Check the Mac's Screen Recording permission.") }
    }
    func axWindow(_ window: SCWindow) -> AXUIElement? {
        guard let pid = window.owningApplication?.processID, let rect = windowBounds(window.windowID) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let candidates = value as? [AXUIElement] else { return nil }
        return candidates.first { element in
            guard let bounds = axBounds(element) else { return false }
            return abs(bounds.minX-rect.minX)<2 && abs(bounds.minY-rect.minY)<2 && abs(bounds.width-rect.width)<2 && abs(bounds.height-rect.height)<2
        }
    }
    func axBounds(_ element: AXUIElement) -> CGRect? {
        var p: CFTypeRef?; var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,kAXPositionAttribute as CFString,&p) == .success,
              AXUIElementCopyAttributeValue(element,kAXSizeAttribute as CFString,&s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point), AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
        return CGRect(origin:point,size:size)
    }
    func enableControl() {
        guard desktopAllowsInput() else { error("Unlock and wake the Mac before enabling remote input."); return }
        guard AXIsProcessTrusted() else { error("Grant Accessibility to LFG Browser Stream on the Mac, then reconnect."); return }
        guard let selected, let pid = selected.owningApplication?.processID,
              let element = axWindow(selected) else { error("Cannot focus that window. Select another window or bring it forward on the Mac."); return }
        NSRunningApplication(processIdentifier:pid)?.activate(options:[])
        guard AXUIElementPerformAction(element,kAXRaiseAction as CFString) == .success else { error("Could not bring the selected window forward."); return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid),kAXFocusedWindowAttribute as CFString,element)
        controlling = true
        wire.send(["type":"control","enabled":true])
    }
    func safeBounds(_ frameID: Int) -> CGRect? {
        guard controlling, desktopAllowsInput(), AXIsProcessTrusted(), let selected,
              let old = output?.current(frameID), let rect = windowBounds(selected.windowID), old == rect,
              abs(selected.frame.width-rect.width)<2, abs(selected.frame.height-rect.height)<2,
              let pid = selected.owningApplication?.processID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        var focus: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),kAXFocusedWindowAttribute as CFString,&focus) == .success,
              let focus, CFGetTypeID(focus) == AXUIElementGetTypeID(),
              let focusedBounds = axBounds(focus as! AXUIElement),
              abs(focusedBounds.minX-rect.minX)<2, abs(focusedBounds.minY-rect.minY)<2,
              abs(focusedBounds.width-rect.width)<2, abs(focusedBounds.height-rect.height)<2 else { return nil }
        return rect
    }
    func command(_ c: [String:Any]) async {
        guard let type = c["type"] as? String else { return }
        switch type {
        case "select": if let id = c["windowId"] as? Int { await select(id) }; return
        case "ack": if let id = c["frameId"] as? Int { output?.acknowledge(id) }; return
        case "control": if c["enabled"] as? Bool == true { enableControl() } else { stopControl() }; return
        default: break
        }
        guard let seq = c["seq"] as? Int, seq > lastSequence,
              let id = c["frameId"] as? Int else { return }
        lastSequence = seq
        guard let rect = safeBounds(id) else {
            stopControl(); error("Control paused because the window moved, lost focus, or the stream became stale. Select the window again after checking it."); return
        }
        switch type {
        case "pointer", "scroll":
            guard let x = c["x"] as? Double, let y = c["y"] as? Double, x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return }
            pointer = CGPoint(x:rect.minX+x*(rect.width-1),y:rect.minY+y*(rect.height-1))
            if type == "scroll" {
                guard let dy = c["dy"] as? Double, dy.isFinite, abs(dy)<=1000 else { return }
                CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:pointer,mouseButton:.left)?.post(tap:.cghidEventTap)
                CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:Int32(dy),wheel2:0,wheel3:0)?.post(tap:.cghidEventTap)
            } else {
                let button: CGMouseButton = c["button"] as? String == "right" ? .right : .left
                let action = c["action"] as? String
                let eventType: CGEventType
                if action == "down" { heldButton = button; eventType = button == .left ? .leftMouseDown : .rightMouseDown }
                else if action == "up" { heldButton = nil; eventType = button == .left ? .leftMouseUp : .rightMouseUp }
                else { eventType = heldButton == .left ? .leftMouseDragged : heldButton == .right ? .rightMouseDragged : .mouseMoved }
                CGEvent(mouseEventSource:nil,mouseType:eventType,mouseCursorPosition:pointer,mouseButton:button)?.post(tap:.cghidEventTap)
            }
        case "text":
            guard let text = c["text"] as? String, text.utf8.count <= 4096 else { return }
            // Commit graphemes individually, preserving surrogate pairs and composed text.
            for character in text {
                let units = Array(String(character).utf16)
                for down in [true,false] {
                    let event = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:down)
                    units.withUnsafeBufferPointer { event?.keyboardSetUnicodeString(stringLength:units.count,unicodeString:$0.baseAddress) }
                    event?.post(tap:.cghidEventTap)
                }
            }
        case "key":
            let keys: [String:CGKeyCode] = ["enter":36,"tab":48,"backspace":51,"escape":53,"left":123,"right":124,"down":125,"up":126,"selectAll":0]
            guard let key = c["key"] as? String, let code = keys[key] else { return }
            for down in [true,false] {
                let event = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)
                if key == "selectAll" { event?.flags = .maskCommand }
                event?.post(tap:.cghidEventTap)
            }
        default: break
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.stopControl(); self.error("Window capture stopped. Reconnect to retry.") }
    }
    func shutdown() async {
        stopControl(); output?.stop()
        if let stream { try? await stream.stopCapture() }
        Darwin.exit(0)
    }
}

MainActor.assumeIsolated {
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let host = StreamHost()
if CommandLine.arguments.contains("--status") {
    wire.send(["type":"status","desktopAllowsInput":desktopAllowsInput(),
               "screenRecording":CGPreflightScreenCaptureAccess(),"accessibility":AXIsProcessTrusted()])
    Darwin.exit(0)
}
let inputWatchdog = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { _ in
    Task { @MainActor in
        if host.controlling && !desktopAllowsInput() {
            host.stopControl(); host.error("The Mac locked or went to sleep. Unlock it before enabling control again.")
        }
    }
}
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { Task { @MainActor in await host.shutdown() } }
termination.resume()
#if DEBUG
if CommandLine.arguments.contains("--test-window") {
    app.setActivationPolicy(.regular)
    let fixture = StreamTestWindow()
    withExtendedLifetime(fixture) { app.run() }
    Darwin.exit(0)
}
#endif
if CommandLine.arguments.contains("--stdio") {
    // Coordinate across LFG servers/worktrees too; flock releases on process exit.
    let lockDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.eugenechan.lfg-stream-host")
    try? FileManager.default.createDirectory(at:lockDirectory,withIntermediateDirectories:true)
    let lockFD = Darwin.open(lockDirectory.appendingPathComponent("controller.lock").path,O_CREAT | O_RDWR,S_IRUSR | S_IWUSR)
    guard lockFD >= 0, flock(lockFD,LOCK_EX | LOCK_NB) == 0 else {
        wire.send(["type":"error","message":"Another connection is streaming this Mac. Close it and reconnect."])
        Darwin.exit(1)
    }
    // A single sequential reader preserves select/control/input order across awaits.
    Task { @MainActor in
        await host.list()
        do {
        for try await line in FileHandle.standardInput.bytes.lines {
            if line.utf8.count <= 8192, let data = line.data(using:.utf8),
               let c = try? JSONSerialization.jsonObject(with:data) as? [String:Any] { await host.command(c) }
        }
        } catch {}
        await host.shutdown()
    }
} else {
    // Local setup only. Never trigger consent dialogs in response to network input.
    CGRequestScreenCaptureAccess()
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    let alert = NSAlert()
    alert.messageText = "LFG Browser Stream"
    alert.informativeText = "Enable Screen Recording and Accessibility for this app in System Settings, then reconnect Browser Stream on your iPhone. Your Mac must remain unlocked."
    alert.runModal()
    Darwin.exit(0)
}
app.run()

}

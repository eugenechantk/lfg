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

/// Video goes straight to Apple's decoder/display layer, outside SwiftUI's
/// update cycle. Only connection and geometry changes invalidate the view.
@MainActor
final class SpaceVideoPlayer: ObservableObject {
    let layer = AVSampleBufferDisplayLayer()
    @Published var connected = false
    @Published var hasFrame = false
    @Published var error: String?
    @Published var aspect: CGFloat = 1.6
    private var format: CMVideoFormatDescription?
    private var epoch: Int?
    private var socket: URLSessionWebSocketTask?
    private var sessionID = ""

    func watch(_ request: URLRequest) async {
        disconnect()
        error = nil; hasFrame = false; epoch = nil; format = nil
        layer.videoGravity = .resizeAspect
        let connection = URLSession.shared.webSocketTask(with: request)
        connection.maximumMessageSize = 65 * 1024 * 1024
        socket = connection; connection.resume()
        defer { if socket === connection { disconnect() } }
        do {
            try await withTaskCancellationHandler {
                while !Task.isCancelled {
                    let message = try await connection.receive()
                    try Task.checkCancellation()
                    switch message {
                    case .data(let data):
                        // Audio is not requested by the player. RCDP audio uses
                        // a separate RAU2 header; do not treat it as video.
                        if data.prefix(4) == Data("RAU2".utf8) { continue }
                        let frame = try SpaceVideoPacket(data)
                        try display(frame)
                    case .string(let text):
                        if let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                            if value["type"] as? String == "session_opened" { connected = true }
                            if value["type"] as? String == "error" { throw MessageSpaceError(message: "The Space could not stream its desktop. Reconnect to try again.") }
                            if value["type"] as? String == "lifecycle", let payload = value["payload"] as? [String: Any], payload["kind"] as? String == "closed" { throw MessageSpaceError(message: "The Space desktop closed.") }
                        }
                    @unknown default: break
                    }
                }
            } onCancel: { connection.cancel(with: .goingAway, reason: nil) }
        } catch {
            if !Task.isCancelled { self.error = "Live view disconnected. \(error.localizedDescription)" }
        }
    }
    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil; connected = false
        layer.flushAndRemoveImage()
    }
    private func display(_ frame: SpaceVideoPacket) throws {
        let d = frame.descriptor
        guard d.codec == "h264" else { throw MessageSpaceError(message: "This Space needs H.264 video support. Update its Cua image.") }
        sessionID = d.session_id
        let units = SpaceVideoPacket.nalUnits(frame.payload)
        if epoch != d.codec_epoch || layer.status == .failed {
            guard d.keyframe,
                  let sps = units.first(where: { $0.first.map { $0 & 31 == 7 } ?? false }),
                  let pps = units.first(where: { $0.first.map { $0 & 31 == 8 } ?? false }) else { return }
            layer.flushAndRemoveImage()
            let result = sps.withUnsafeBytes { a in
                pps.withUnsafeBytes { b in
                    let pointers = [a.bindMemory(to: UInt8.self).baseAddress!, b.bindMemory(to: UInt8.self).baseAddress!]
                    let sizes = [sps.count, pps.count]
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers, parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
                }
            }
            guard result == noErr else { throw MessageSpaceError(message: "The Space video format could not be decoded.") }
            epoch = d.codec_epoch
        }
        guard let format else { return }
        var avcc = Data()
        for unit in units where !unit.isEmpty {
            var length = UInt32(unit.count).bigEndian
            avcc.append(Data(bytes: &length, count: 4)); avcc.append(unit)
        }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block) == noErr, let block else { return }
        let copied = avcc.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count) }
        guard copied == noErr else { return }
        var sample: CMSampleBuffer?
        var size = avcc.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let values = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(values, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        layer.enqueue(sample)
        if !hasFrame { hasFrame = true }
        let ratio = CGFloat(d.width_px) / CGFloat(d.height_px)
        if aspect != ratio { aspect = ratio }
        // Latest-frame acknowledgement prevents a slow viewer from building a queue.
        let ack: [String: Any] = ["type": "frame_ack", "payload": ["session_id": sessionID, "sequence": d.sequence, "decode_queue": 0]]
        if let data = try? JSONSerialization.data(withJSONObject: ack), let text = String(data: data, encoding: .utf8) {
            socket?.send(.string(text)) { _ in }
        }
    }
}

/// Pointer traffic stays outside SwiftUI observation. Only errors change UI state.
@MainActor
final class SpaceInputDispatcher: ObservableObject {
    private var pending: [(String, [String: String])] = []
    private var sending = false
    private var generation = 0
    func stop() { generation += 1; pending.removeAll() }
    func submit(_ action: String, _ values: [String: String], client: MessageSpacesClient, id: String, failed: @escaping (String) -> Void) {
        if action == "move", pending.last?.0 == "move" { pending.removeLast() }
        guard pending.count < 256 else { stop(); failed("Input could not keep up. Take control again."); return }
        if action == "type", pending.last?.0 == "type",
           let previous = pending.last?.1["text"], let next = values["text"], previous.utf16.count + next.utf16.count <= 8000 {
            pending.removeLast(); pending.append(("type", ["text": previous + next]))
        } else { pending.append((action, values)) }
        guard !sending else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            while !pending.isEmpty {
                let next = pending.removeFirst(), current = generation
                do { _ = try await client.browser(id, action: next.0, values: next.1) }
                catch {
                    if current == generation { stop(); failed(error.localizedDescription) }
                }
            }
        }
    }
}

struct SpaceLiveView: View {
    let client: MessageSpacesClient
    let space: MessageSpace
    @StateObject private var player = SpaceVideoPlayer()
    @Environment(\.scenePhase) private var scenePhase
    @State private var reconnect = 0
    @State private var keyboard = false
    @StateObject private var dispatcher = SpaceInputDispatcher()
    @State private var controlling = false
    @State private var busy = false
    @State private var error: String?
    @State private var url = "https://example.com"
    @State private var text = ""
    private var available: Bool { !["stopped", "suspended", "unavailable"].contains(space.powerState) }
    private var watchKey: String {
        #if os(iOS)
        "\(scenePhase == .active)-\(available)-\(reconnect)-\(controlling)"
        #else
        "\(scenePhase == .active)-\(available)-\(reconnect)"
        #endif
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Label(player.connected && player.hasFrame ? "Live" : "Disconnected", systemImage: "circle.fill")
                        .foregroundStyle(player.connected && player.hasFrame ? .green : .secondary)
                        .font(.caption).accessibilityIdentifier("message_live_status")
                    Spacer()
                    Button("Reconnect", systemImage: "arrow.clockwise") { dispatcher.stop(); controlling = false; reconnect += 1 }
                        .disabled(!available).accessibilityIdentifier("message_live_reconnect")
                }
                #if os(iOS)
                if controlling {
                    Color.black.aspectRatio(player.aspect, contentMode: .fit)
                } else { desktop }
                #else
                desktop
                #endif
                if let error = error ?? player.error {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("message_live_error")
                }
                HStack {
                    if controlling {
                        Label("You have control", systemImage: "hand.point.up.left.fill").font(.subheadline)
                        Spacer()
                        #if !os(macOS)
                        Button("Keyboard", systemImage: "keyboard") { keyboard.toggle() }.accessibilityIdentifier("message_live_keyboard")
                        #endif
                        Button("Done") { dispatcher.stop(); keyboard = false; controlling = false }.accessibilityIdentifier("message_live_done")
                    } else {
                        Text("Watch your agent work, or pause it to take over.").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Take control") { Task { await takeControl() } }
                            .buttonStyle(.borderedProminent).disabled(busy || !player.connected || !player.hasFrame)
                            .accessibilityIdentifier("message_live_take_control")
                    }
                }
                if controlling {
                    HStack {
                        TextField("Website URL", text: $url).textFieldStyle(.roundedBorder).accessibilityIdentifier("message_browser_url")
                        Button("Go") { Task { await input("navigate", values: ["url": url]) } }.accessibilityIdentifier("message_browser_go")
                    }
                    HStack {
                        TextField("Text for the focused field", text: $text).textFieldStyle(.roundedBorder).accessibilityIdentifier("message_browser_text")
                        Button("Type") { Task { await input("type", values: ["text": text]); if error == nil { text = "" } } }.accessibilityIdentifier("message_browser_type")
                    }
                    ViewThatFits(in: .horizontal) {
                        keys
                        VStack { keys }
                    }
                    Text("Done returns to watching. Send a message in Chat to give the agent its next instruction.").font(.footnote).foregroundStyle(.secondary)
                }
                if busy { ProgressView(controlling ? "Sending input…" : "Waiting for the agent to pause…").accessibilityIdentifier("message_live_busy") }
            }.padding()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $controlling) {
            SpaceControlFullScreen(client: client, space: space) { controlling = false }
        }
        #endif
        .task(id: watchKey) {
            #if os(iOS)
            if controlling { player.disconnect(); return }
            #else
            controlling = false
            #endif
            guard scenePhase == .active && available else { player.disconnect(); return }
            await player.watch(client.streamRequest(space.id))
        }
        .onChange(of: controlling) { _, active in if !active { keyboard = false; dispatcher.stop() } }
        .onDisappear {
            dispatcher.stop(); player.disconnect()
            #if os(macOS)
            controlling = false
            #endif
        }
        #if os(macOS)
        .onChange(of: player.connected) { _, connected in if !connected { controlling = false } }
        #endif
    }
    private var desktop: some View {
                SpaceInputCanvas(layer: player.layer, active: controlling && player.connected, keyboard: keyboard, send: enqueue)
                    .aspectRatio(player.aspect, contentMode: .fit)
                    .background(.black).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if !player.hasFrame {
                            if available && player.error == nil { ProgressView("Connecting to Space…").tint(.white).foregroundStyle(.white) }
                            else { Text(available ? "Live view unavailable" : "Turn the Space on to watch it").foregroundStyle(.white).padding() }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(controlling ? "Live Space desktop. Tap or drag to control." : "Live Space desktop. Watching agent.")
                    .accessibilityIdentifier("message_live_screen")
    }
    private var keys: some View {
        HStack {
            Button("Enter") { Task { await input("key", values: ["key": "enter"]) } }.accessibilityIdentifier("message_browser_enter")
            Button("Tab") { Task { await input("key", values: ["key": "tab"]) } }.accessibilityIdentifier("message_browser_tab")
            Button("Scroll up", systemImage: "arrow.up") { Task { await input("scroll", values: ["direction": "up"]) } }.accessibilityLabel("Scroll up").accessibilityIdentifier("message_live_scroll_up")
            Button("Scroll down", systemImage: "arrow.down") { Task { await input("scroll", values: ["direction": "down"]) } }.accessibilityLabel("Scroll down").accessibilityIdentifier("message_live_scroll_down")
        }.buttonStyle(.bordered).disabled(busy)
    }
    private func takeControl() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { _ = try await client.browser(space.id, action: "takeControl"); controlling = player.connected }
        catch { self.error = error.localizedDescription }
    }
    private func input(_ action: String, values: [String: String]) async {
        enqueue(action, values)
    }
    private func enqueue(_ action: String, _ values: [String: String]) {
        guard controlling && player.connected else { return }
        dispatcher.submit(action, values, client: client, id: space.id) { message in
            controlling = false; error = message
        }
    }
}

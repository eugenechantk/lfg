#if os(iOS)
import SwiftUI
import LFGCore

struct SpaceControlFullScreen: View {
    let client: MessageSpacesClient
    let space: MessageSpace
    let done: () -> Void
    @StateObject private var player = SpaceVideoPlayer()
    @StateObject private var dispatcher = SpaceInputDispatcher()
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboard = false
    @State private var fitToken = 0
    @State private var reconnect = 0
    @State private var error: String?
    @State private var inputFailed = false
    private var active: Bool { player.connected && player.hasFrame && scenePhase == .active && !inputFailed }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button("Done", systemImage: "xmark") { endControl() }
                    .accessibilityIdentifier("message_control_done")
                Spacer(minLength: 0)
                Text(space.name).font(.subheadline).lineLimit(1)
                Spacer(minLength: 0)
                if player.connected && player.hasFrame {
                    Label("Live", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
                } else {
                    Button("Reconnect", systemImage: "arrow.clockwise") { keyboard = false; dispatcher.stop(); reconnect += 1 }
                        .accessibilityIdentifier("message_control_reconnect")
                }
            }.padding(.horizontal).frame(minHeight: 48)
            ZStack {
                SpaceZoomCanvas(layer: player.layer, aspect: player.aspect, active: active, keyboard: keyboard, fitToken: fitToken, send: send)
                    .accessibilityLabel("Space desktop. Pinch to zoom. Drag with one finger to control. Pan with two fingers. Tap with two fingers to right-click.")
                    .accessibilityIdentifier("message_control_screen")
                if !player.hasFrame && player.error == nil { ProgressView("Connecting to Space…").tint(.white) }
            }
            if let error = error ?? player.error {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                    .accessibilityIdentifier("message_control_error")
            }
            HStack(spacing: 0) {
                control("Fit", icon: "arrow.down.right.and.arrow.up.left", id: "message_control_fit") { fitToken += 1 }
                control(keyboard ? "Hide keyboard" : "Keyboard", icon: keyboard ? "keyboard.chevron.compact.down" : "keyboard", id: "message_control_keyboard") { keyboard.toggle() }
                control("Tab", icon: "arrow.right.to.line", id: "message_control_tab") { send("key", ["key":"tab"]) }
                control("Escape", icon: "escape", id: "message_control_escape") { send("key", ["key":"escape"]) }
                control("Enter", icon: "return", id: "message_control_enter") { send("key", ["key":"enter"]) }
            }.padding(.horizontal, 8).frame(minHeight: 52)
            if !keyboard {
                Text("Pinch to zoom · Two fingers to pan or right-click")
                    .font(.caption2).foregroundStyle(.gray).padding(.bottom, 6)
            }
        }
        .background(.black).foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .interactiveDismissDisabled()
        .onAppear { SpaceControlOrientation.setControlling(true) }
        .onDisappear { dispatcher.stop(); keyboard = false; player.disconnect(); SpaceControlOrientation.setControlling(false) }
        .task(id: "\(scenePhase == .active)-\(reconnect)") {
            dispatcher.stop(); keyboard = false
            guard scenePhase == .active else { player.disconnect(); return }
            await player.watch(client.streamRequest(space.id))
        }
        .onChange(of: player.connected) { _, connected in if !connected { dispatcher.stop(); keyboard = false } }
    }
    private func control(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(maxWidth: .infinity, minHeight: 44) }
            .accessibilityLabel(title).accessibilityIdentifier(id)
            .disabled(!active && id != "message_control_fit")
    }
    private func send(_ action: String, _ values: [String: String]) {
        guard active else { return }
        dispatcher.submit(action, values, client: client, id: space.id) { message in
            error = message; inputFailed = true; keyboard = false
        }
    }
    private func endControl() { dispatcher.stop(); keyboard = false; player.disconnect(); done() }
}
#endif

import SwiftUI
import LFGCore

struct IPhonePreviewSheet: View {
    let sessionID: String
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let preview = store.iPhonePreview(for: sessionID) {
                    IPhonePreviewPanel(preview: preview, host: store.host(forSession: sessionID)?.label ?? "Mac")
                } else {
                    ContentUnavailableView("Host unavailable", systemImage: "desktopcomputer",
                        description: Text("Connect to this session's Mac to view its iPhone."))
                        .accessibilityIdentifier("iphone_preview_no_host")
                }
            }
            .navigationTitle("iPhone Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("iphone_preview_done")
                }
            }
        }
        .accessibilityIdentifier("iphone_preview_sheet")
    }
}

private struct IPhonePreviewPanel: View {
    let preview: IPhonePreviewSession
    let host: String
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 12) {
            if preview.isLoading {
                ProgressView("Finding iPhones…")
                    .accessibilityIdentifier("iphone_preview_loading")
            } else if preview.devices.isEmpty {
                ContentUnavailableView("No iPhones configured", systemImage: "iphone.slash",
                    description: Text(preview.error ?? "Set up iphone-control on \(host) to add a phone."))
                    .accessibilityIdentifier("iphone_preview_empty")
                Button("Retry") { Task { await preview.load() } }
                    .accessibilityIdentifier("iphone_preview_retry")
            } else {
                HStack {
                    Picker("iPhone", selection: Binding(
                        get: { preview.selectedDeviceID ?? "" },
                        set: { preview.select($0) }
                    )) {
                        ForEach(preview.devices) { phone in Text(phone.name).tag(phone.id) }
                    }
                    .disabled(preview.isEnabled || preview.isChanging)
                    .accessibilityIdentifier("iphone_preview_device")
                    Spacer()
                    Text(host).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Live preview", isOn: Binding(
                    get: { preview.isEnabled },
                    set: { preview.setEnabled($0) }
                ))
                .disabled(preview.isChanging || scenePhase != .active)
                .accessibilityIdentifier("iphone_preview_toggle")

                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.black)
                        if let data = preview.frame, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .accessibilityLabel("Live iPhone screen")
                                .accessibilityIdentifier("iphone_preview_frame")
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: preview.isEnabled ? "iphone" : "video.slash")
                                    .font(.largeTitle)
                                Text(preview.status).multilineTextAlignment(.center)
                                    .font(.callout).padding(.horizontal, 24)
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .accessibilityIdentifier("iphone_preview_placeholder")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(preview.status).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("iphone_preview_status")
                Text("View only · Stops when closed or in the background")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .task { await preview.load() }
        .onDisappear { preview.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { preview.stop() } }
    }
}

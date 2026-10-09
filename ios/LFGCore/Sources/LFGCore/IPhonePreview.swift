import Foundation
import Observation

public struct IPhonePreviewDevice: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public protocol IPhonePreviewTransport: Sendable {
    func iPhonePreviewDevices() async throws -> [IPhonePreviewDevice]
    func setIPhonePreview(_ device: String, enabled: Bool) async throws
    func iPhonePreviewFrame(_ device: String) async throws -> Data?
}

/// A short-lived viewing lease, owned by SessionStore. Controls are serialized;
/// frames are cancellable and discarded whenever the viewing generation changes.
@MainActor @Observable
public final class IPhonePreviewSession {
    public private(set) var devices: [IPhonePreviewDevice] = []
    public private(set) var selectedDeviceID: String?
    public private(set) var isEnabled = false
    public private(set) var isChanging = false
    public private(set) var isLoading = false
    public private(set) var frame: Data?
    public private(set) var error: String?
    public var status: String {
        if let error { return error }
        if isChanging { return isEnabled ? "Connecting…" : "Stopping…" }
        return isEnabled ? (frame == nil ? "Waiting for the iPhone…" : "Live") : "Preview is off"
    }
    @ObservationIgnored private let transport: any IPhonePreviewTransport
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var controlTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?

    public init(transport: any IPhonePreviewTransport) { self.transport = transport }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            devices = try await transport.iPhonePreviewDevices()
            if !devices.contains(where: { $0.id == selectedDeviceID }) { select(devices.first?.id) }
            error = nil
        } catch { self.error = "Could not list iPhones. Check the host connection and try again." }
    }

    public func select(_ id: String?) {
        guard id != selectedDeviceID else { return }
        stop()
        selectedDeviceID = id
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Task<Void, Never> {
        generation += 1
        let epoch = generation
        frameTask?.cancel()
        frameTask = nil
        frame = nil
        error = nil
        let previous = controlTask
        guard let device = selectedDeviceID else {
            isEnabled = false
            return Task {}
        }
        isEnabled = enabled
        isChanging = true
        let task = Task { [weak self, transport] in
            // Do not cancel a start request: the server may still apply it.
            // A later off request must follow its result, even after dismissal.
            await previous?.value
            do {
                try await transport.setIPhonePreview(device, enabled: enabled)
                guard let self, self.generation == epoch else { return }
                self.isChanging = false
                if enabled { self.poll(device, epoch: epoch) }
            } catch {
                guard let self, self.generation == epoch else { return }
                self.isEnabled = false
                self.isChanging = false
                self.frame = nil
                self.error = enabled
                    ? "Preview is unavailable. Connect this iPhone and start iphone-control on its Mac, then try again."
                    : "Preview stopped locally. The host will stop capture when its viewing lease expires."
            }
        }
        controlTask = task
        return task
    }

    public func stop() {
        guard isEnabled || isChanging else { frame = nil; return }
        setEnabled(false)
    }

    private func poll(_ device: String, epoch: Int) {
        frameTask = Task { [weak self, transport] in
            do {
                while !Task.isCancelled {
                    let frame = try await transport.iPhonePreviewFrame(device)
                    guard let self, self.generation == epoch, !Task.isCancelled else { return }
                    self.frame = frame
                    try await Task.sleep(for: .milliseconds(333))
                }
            } catch {
                guard let self, self.generation == epoch, !Task.isCancelled else { return }
                self.stop()
                // Preserve the actionable error after the best-effort pause.
                await self.controlTask?.value
                guard self.generation == epoch + 1 else { return }
                self.error = "The preview disconnected. Check the iPhone connection and turn Live preview on to retry."
            }
        }
    }
}

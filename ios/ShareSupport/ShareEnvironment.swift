import Foundation
import LFGCore

/// Compiled into both targets. Secrets are never copied into this container.
enum ShareEnvironment {
    static let groupID = "group.com.eugenechan.lfg"
    static var spool: ShareSpool? {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        return ShareSpool(root: root.appendingPathComponent("Shares", isDirectory: true))
    }
    static var transport: ShareTransport {
        .live { HostCredentialStore.shared.client(forHostURL: $0.url) }
    }
}

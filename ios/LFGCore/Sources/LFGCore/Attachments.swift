import Foundation

// MARK: - Outgoing attachments
//
// The composer can attach anything now — a photo, a screen recording, a PDF, a
// CSV — and every one of those has to survive three hops with its identity
// intact: upload (filename header), the host's filesystem (a real name on disk,
// because that name is what the transcript card shows), and the offline outbox
// (a sidecar on disk that may sit through an app kill before it replays).
//
// All of that is string work with sharp edges — traversal, spaces, absent
// extensions, a legacy sidecar format — so it lives here, pure and tested,
// rather than in the SwiftUI layer where it would need a simulator to exercise.

public enum AttachmentKind: String, Codable, Sendable, Equatable {
    case image, video, file

    public static func from(ext: String) -> AttachmentKind {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif":
            return .image
        case "mp4", "mov", "m4v", "webm", "avi", "mkv":
            return .video
        default:
            return .file
        }
    }
}

/// Everything the host needs to store an attachment under a name a human will
/// recognise, and everything the outbox needs to replay it after a cold start.
public struct AttachmentMeta: Codable, Sendable, Equatable {
    /// Already sanitized — safe as a path component and as a bare token in the
    /// message text. Always carries an extension.
    public let filename: String
    public let contentType: String
    public let kind: AttachmentKind

    public init(filename: String, contentType: String, kind: AttachmentKind) {
        self.filename = filename
        self.contentType = contentType
        self.kind = kind
    }

    /// Build from a raw, untrusted filename, inferring the rest.
    public init(rawFilename: String, contentType: String? = nil, fallbackExtension: String = "dat") {
        let safe = AttachmentNaming.sanitize(filename: rawFilename, fallbackExtension: fallbackExtension)
        let ext = (safe as NSString).pathExtension
        self.filename = safe
        self.contentType = contentType ?? AttachmentNaming.contentType(forExtension: ext)
        self.kind = AttachmentKind.from(ext: ext)
    }
}

public enum AttachmentNaming {
    /// Characters allowed to survive into a stored filename. Everything else
    /// collapses to `_` — including whitespace, which matters more than it looks:
    /// the upload path is appended to the message text as a bare token, and both
    /// `MediaScanner`'s bare-ref regex and the agent's own path handling stop at
    /// the first space. A lost space beats an unopenable file.
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    /// Longest stored name. Keeps us well inside every filesystem's 255-byte
    /// component limit even after multi-byte characters expand.
    public static let maxLength = 120

    /// Reduce an arbitrary user- or system-supplied name to something safe to use
    /// as a single path component, preserving the extension (which is what drives
    /// content type, icon, and whether the agent can read it at all).
    public static func sanitize(filename: String, fallbackExtension: String = "dat") -> String {
        // Take the last path component first: a name arriving as `../../etc/passwd`
        // or `C:\evil\x.exe` must not be able to steer where the bytes land.
        let lastComponent = filename
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? ""

        var base = (lastComponent as NSString).deletingPathExtension
        var ext = (lastComponent as NSString).pathExtension

        base = scrub(base)
        ext = scrub(ext).lowercased()

        // `..`, `.`, and a name that was nothing but separators all reduce to
        // something with no identity left — give them one.
        if base.isEmpty || base.allSatisfy({ $0 == "." || $0 == "_" }) { base = "file" }
        if ext.isEmpty { ext = scrub(fallbackExtension).lowercased() }
        if ext.isEmpty { ext = "dat" }
        if ext.count > 12 { ext = String(ext.prefix(12)) }

        // Truncate the base, never the extension.
        let budget = maxLength - ext.count - 1
        if budget > 0, base.count > budget { base = String(base.prefix(budget)) }

        return "\(base).\(ext)"
    }

    private static func scrub(_ s: String) -> String {
        var out = ""
        var lastWasUnderscore = false
        for ch in s {
            if allowed.contains(ch) {
                out.append(ch)
                lastWasUnderscore = false
            } else if !lastWasUnderscore {
                // Collapse runs — "my  long   name.pdf" shouldn't become "my__long___name.pdf".
                out.append("_")
                lastWasUnderscore = true
            }
        }
        // Leading dots would make the file hidden and, worse, `.` / `..` are
        // traversal in disguise once the extension is stripped off.
        while out.hasPrefix(".") { out.removeFirst() }
        while out.hasSuffix("_") { out.removeLast() }
        return out
    }

    /// Extension → MIME type. Deliberately small: it covers what people actually
    /// hand an agent from a phone, and anything unrecognised is honestly labelled
    /// `application/octet-stream` rather than guessed at.
    public static func contentType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "webm": return "video/webm"
        case "pdf": return "application/pdf"
        case "txt", "log": return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "html", "htm": return "text/html"
        case "zip": return "application/zip"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        default: return "application/octet-stream"
        }
    }

    /// Inverse of the above, for the few cases where only a MIME type is known
    /// (a `PhotosPickerItem`'s `supportedContentTypes`, a bare upload).
    public static func fileExtension(forContentType type: String) -> String? {
        let t = type.lowercased().split(separator: ";").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        switch t {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/x-m4v": return "m4v"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        case "text/markdown": return "md"
        case "text/csv": return "csv"
        case "application/json": return "json"
        case "application/zip": return "zip"
        default: return nil
        }
    }
}

// MARK: - Offline outbox sidecars
//
// A send made with no host reachable parks its bytes on disk next to the outbox
// row and replays them on reconnect. The sidecar's own *name* carries the
// ordering and the original filename — self-describing, so there is no manifest
// to fall out of sync with the files it describes.

public enum OutboxAttachmentNaming {
    private static let separator = "__"

    /// `0__quarterly_report.pdf`
    public static func sidecarName(index: Int, filename: String) -> String {
        "\(index)\(separator)\(AttachmentNaming.sanitize(filename: filename))"
    }

    /// Parse a sidecar name back into its ordering and metadata.
    ///
    /// Also accepts the **legacy** `<index>.png` shape written before attachments
    /// were anything but photos. Messages queued by the previous build are
    /// sitting on real devices right now; refusing to read them would silently
    /// drop someone's offline message on upgrade.
    public static func parse(sidecarName name: String) -> (index: Int, meta: AttachmentMeta)? {
        if let range = name.range(of: separator),
           let index = Int(name[name.startIndex..<range.lowerBound]) {
            let filename = String(name[range.upperBound...])
            guard !filename.isEmpty else { return nil }
            return (index, AttachmentMeta(rawFilename: filename))
        }
        // Legacy: bare `<index>.png`.
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "png", let index = Int(stem) {
            return (index, AttachmentMeta(filename: "image.png", contentType: "image/png", kind: .image))
        }
        return nil
    }

    /// Sidecars in send order. Anything unparseable is dropped rather than
    /// replayed at an arbitrary position.
    public static func ordered(sidecarNames names: [String]) -> [(index: Int, meta: AttachmentMeta, name: String)] {
        names
            .compactMap { name -> (index: Int, meta: AttachmentMeta, name: String)? in
                guard let p = parse(sidecarName: name) else { return nil }
                return (p.index, p.meta, name)
            }
            .sorted { $0.index == $1.index ? $0.name < $1.name : $0.index < $1.index }
    }
}

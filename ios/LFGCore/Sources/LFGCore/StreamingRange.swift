import Foundation

/// Pure helpers behind the app's streaming video loader
/// (`StreamingResourceLoader` in `RichContent.swift`).
///
/// AVPlayer fetches remote media in byte ranges. Cloudflare Access refuses a
/// request that lacks the service-token headers (the `CF_Authorization` cookie
/// alone is a 403 — verified 2026-09-17), and AVFoundation has no supported way
/// to add headers, so the app answers AVPlayer's range requests itself through
/// `LFGClient.resourceRequest(for:)`. Everything that can be reasoned about
/// without AVFoundation lives here so `swift test` covers it.
public enum StreamingRange {
    /// The `Range` header for one resource-loader data request.
    ///
    /// - `toEnd`: AVPlayer's `requestsAllDataToEndOfResource` — an open range
    ///   (`bytes=N-`) so the server streams the rest and the player starts as
    ///   soon as it has enough.
    public static func header(offset: Int64, length: Int, toEnd: Bool) -> String {
        let start = max(0, offset)
        if toEnd || length <= 0 { return "bytes=\(start)-" }
        return "bytes=\(start)-\(start + Int64(length) - 1)"
    }

    /// Total resource length from a `206` response's `Content-Range`
    /// (`bytes 0-1/235826042`), or from `Content-Length` on a plain `200`.
    /// Nil when neither is usable — the player then streams without a known
    /// duration, which still plays.
    public static func totalLength(contentRange: String?, contentLength: Int64?) -> Int64? {
        if let contentRange {
            let trimmed = contentRange.trimmingCharacters(in: .whitespaces)
            if let slash = trimmed.lastIndex(of: "/") {
                let total = trimmed[trimmed.index(after: slash)...].trimmingCharacters(in: .whitespaces)
                if let n = Int64(total), n >= 0 { return n }
            }
        }
        if let contentLength, contentLength >= 0 { return contentLength }
        return nil
    }

    /// Uniform type identifier AVFoundation expects in
    /// `contentInformationRequest.contentType`, from the response MIME type
    /// with an extension fallback for servers that answer `octet-stream`.
    public static func uniformType(mimeType: String?, pathExtension: String) -> String {
        switch mimeType?.lowercased().split(separator: ";").first.map(String.init) {
        case "video/mp4", "video/x-m4v": return "public.mpeg-4"
        case "video/quicktime": return "com.apple.quicktime-movie"
        case "audio/mp4", "audio/x-m4a": return "public.mpeg-4-audio"
        default: break
        }
        switch pathExtension.lowercased() {
        case "mov": return "com.apple.quicktime-movie"
        case "m4a": return "public.mpeg-4-audio"
        default: return "public.mpeg-4"
        }
    }
}

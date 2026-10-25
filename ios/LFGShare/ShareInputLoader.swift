import Foundation
import UIKit
import UniformTypeIdentifiers
import LFGCore

@MainActor
struct ShareInputLoader {
    struct Input {
        var id = UUID().uuidString
        var text = ""
        var previewTitle: String?
        var files: [ShareFile] = []
    }

    static func load(_ items: [NSExtensionItem], spool: ShareSpool) async throws -> Input {
        var input = Input()
        var parts: [String] = []
        do {
            for item in items {
                if let text = item.attributedContentText?.string, !text.isEmpty { parts.append(text) }
                for provider in item.attachments ?? [] {
                    if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                       let page = try? await pageInfo(provider) {
                        input.previewTitle = page.title
                        if !page.selection.isEmpty, !parts.contains(page.selection) { parts.append(page.selection) }
                        if !page.url.isEmpty, !parts.contains(where: { $0.contains(page.url) }) { parts.append(page.url) }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                       !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let url = try await string(provider, type: UTType.url.identifier)
                        if !parts.contains(where: { $0.contains(url) }) { parts.append(url) }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                                provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
                                provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) &&
                                !provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        guard input.files.count < 10 else { throw ShareCaptureError.tooLarge }
                        let type = provider.registeredTypeIdentifiers.first(where: {
                            guard let type = UTType($0) else { return false }
                            return type.conforms(to: .data) && !type.conforms(to: .url)
                        }) ?? UTType.data.identifier
                        let file = try await stage(provider, type: type, spool: spool, id: input.id)
                        input.files.append(file)
                        guard input.files.reduce(0, { $0 + $1.byteCount }) <= ShareSpool.maximumTotalBytes else { throw ShareCaptureError.tooLarge }
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        let text = try await string(provider, type: UTType.plainText.identifier)
                        if !text.isEmpty, !parts.contains(text) { parts.append(text) }
                    } else { throw ShareCaptureError.invalidFile }
                }
            }
            input.text = parts.joined(separator: "\n")
            guard !input.text.isEmpty || !input.files.isEmpty else { throw ShareCaptureError.empty }
            return input
        } catch {
            try? spool.discard(input.id)
            throw error
        }
    }

    private struct PageInfo: Sendable { var title: String?; var selection: String; var url: String }
    private static func pageInfo(_ provider: NSItemProvider) async throws -> PageInfo {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) { value, error in
                if let error { continuation.resume(throwing: error); return }
                guard let dictionary = value as? [String: Any],
                      let page = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else {
                    continuation.resume(throwing: ShareCaptureError.invalidFile); return
                }
                continuation.resume(returning: PageInfo(title: page["title"] as? String,
                    selection: page["selection"] as? String ?? "", url: page["url"] as? String ?? ""))
            }
        }
    }

    private static func string(_ provider: NSItemProvider, type: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = value as? URL { continuation.resume(returning: url.absoluteString) }
                else if let text = value as? String { continuation.resume(returning: text) }
                else if let data = value as? Data, let text = String(data: data, encoding: .utf8) { continuation.resume(returning: text) }
                else { continuation.resume(throwing: ShareCaptureError.invalidFile) }
            }
        }
    }

    private static func stage(_ provider: NSItemProvider, type: String, spool: ShareSpool, id: String) async throws -> ShareFile {
        let suggestedName = provider.suggestedName
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           !provider.hasItemConformingToTypeIdentifier(type) {
            return try await stageFileURL(provider, spool: spool, id: id)
        }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else { continuation.resume(throwing: error ?? ShareCaptureError.invalidFile); return }
                do {
                    let content = UTType(type) ?? .data
                    var name = suggestedName ?? url.lastPathComponent
                    if URL(fileURLWithPath: name).pathExtension.isEmpty, let ext = content.preferredFilenameExtension { name += "." + ext }
                    let file = try spool.stage(url, jobID: id, filename: name, contentType: content.preferredMIMEType ?? "application/octet-stream")
                    continuation.resume(returning: file)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func stageFileURL(_ provider: NSItemProvider, spool: ShareSpool, id: String) async throws -> ShareFile {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { value, error in
                guard let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:)), url.isFileURL else {
                    continuation.resume(throwing: error ?? ShareCaptureError.invalidFile); return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let type = UTType(filenameExtension: url.pathExtension) ?? .data
                    continuation.resume(returning: try spool.stage(url, jobID: id, filename: suggestedName ?? url.lastPathComponent,
                        contentType: type.preferredMIMEType ?? "application/octet-stream"))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

}

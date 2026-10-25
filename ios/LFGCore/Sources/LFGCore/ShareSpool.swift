import Foundation
import Darwin

/// Small App Group spool, separate from the app's database. A per-job OS lease
/// excludes simultaneous app/extension delivery and is released on process death.
public struct ShareSpool: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public static let maximumFileBytes = 64 * 1024 * 1024
    public static let maximumTotalBytes = 128 * 1024 * 1024

    public func saveConfiguration(_ configuration: ShareConfiguration) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(configuration).write(to: root.appendingPathComponent("configuration.json"), options: .atomic)
    }
    public func configuration() -> ShareConfiguration {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("configuration.json")),
              let value = try? JSONDecoder().decode(ShareConfiguration.self, from: data) else { return .init() }
        return value
    }
    public func directory(_ id: String) -> URL {
        root.appendingPathComponent("jobs", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }
    public func fileURL(jobID: String, file: ShareFile) -> URL {
        directory(jobID).appendingPathComponent(file.id)
    }
    public func save(_ job: ShareJob) throws {
        guard UUID(uuidString: job.id) != nil else { throw ShareCaptureError.invalidFile }
        let dir = directory(job.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(job).write(to: dir.appendingPathComponent("job.json"), options: .atomic)
    }
    public func load(_ id: String) throws -> ShareJob {
        try JSONDecoder().decode(ShareJob.self, from: Data(contentsOf: directory(id).appendingPathComponent("job.json")))
    }
    public func jobs() -> [ShareJob] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("jobs"),
                                                                includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { try? load($0.lastPathComponent) }.sorted { $0.createdAt < $1.createdAt }
    }
    /// Copy provider-owned files while their completion-handler URL is valid.
    public func stage(_ source: URL, jobID: String, filename: String, contentType: String) throws -> ShareFile {
        let count = (try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard count > 0 else { throw ShareCaptureError.invalidFile }
        guard count < Self.maximumFileBytes else { throw ShareCaptureError.tooLarge }
        let file = ShareFile(filename: URL(fileURLWithPath: filename).lastPathComponent,
                             contentType: contentType, byteCount: count)
        let dir = directory(jobID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: fileURL(jobID: jobID, file: file))
        return file
    }
    public func lease(_ id: String) throws -> ShareLease? {
        try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: true)
        let fd = open(directory(id).appendingPathComponent("lease").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ShareCaptureError.unavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        return ShareLease(fd: fd)
    }
    public func removeFiles(_ job: ShareJob) {
        for file in job.files { try? FileManager.default.removeItem(at: fileURL(jobID: job.id, file: file)) }
    }
    public func discard(_ id: String) throws {
        guard let lease = try lease(id) else { return }
        defer { lease.release() }
        try FileManager.default.removeItem(at: directory(id))
    }
}

public final class ShareLease: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var released = false
    fileprivate init(fd: Int32) { self.fd = fd }
    public func release() {
        lock.lock(); defer { lock.unlock() }
        guard !released else { return }
        released = true; flock(fd, LOCK_UN); close(fd)
    }
    deinit { release() }
}

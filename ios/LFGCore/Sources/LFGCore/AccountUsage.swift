import Foundation
import Observation

private func usageTimestamp(_ c: KeyedDecodingContainer<UsageDateKey>, key: UsageDateKey) -> Double? {
    if let number = try? c.decode(Double.self, forKey: key), number.isFinite { return number }
    guard let text = try? c.decode(String.self, forKey: key) else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date.timeIntervalSince1970 * 1000 }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text).map { $0.timeIntervalSince1970 * 1000 }
}
private enum UsageDateKey: String, CodingKey { case fetchedAt, resetsAt }

public struct AccountQuotaWindow: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var durationMinutes: Double
    public var name: String?
    public var usedPercent: Double?
    /// Unix milliseconds, converted from the host's ISO timestamp at decoding.
    public var resetsAt: Double?
    public init(id: String, durationMinutes: Double, name: String? = nil, usedPercent: Double? = nil, resetsAt: Double? = nil) {
        self.id = id; self.durationMinutes = durationMinutes; self.name = name
        self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }
    private enum CodingKeys: String, CodingKey { case id, durationMinutes, name, usedPercent, resetsAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        durationMinutes = (try? c.decode(Double.self, forKey: .durationMinutes)) ?? 0
        id = (try? c.decode(String.self, forKey: .id)) ?? "window-\(durationMinutes)"
        name = try? c.decode(String.self, forKey: .name)
        usedPercent = try? c.decode(Double.self, forKey: .usedPercent)
        resetsAt = usageTimestamp(try decoder.container(keyedBy: UsageDateKey.self), key: .resetsAt)
    }
}

public struct AccountUsageProvider: Codable, Sendable, Hashable {
    public var provider: String
    public var accountId: String?
    public var accountLabel: String?
    public var plan: String?
    public var status: String
    public var fetchedAt: Double?
    public var windows: [AccountQuotaWindow]
    public var error: String?
    public init(provider: String, accountId: String? = nil, accountLabel: String? = nil, plan: String? = nil,
                status: String = "ok", fetchedAt: Double? = nil, windows: [AccountQuotaWindow] = [], error: String? = nil) {
        self.provider = provider; self.accountId = accountId; self.accountLabel = accountLabel; self.plan = plan
        self.status = status; self.fetchedAt = fetchedAt; self.windows = windows; self.error = error
    }
    private enum CodingKeys: String, CodingKey { case provider, accountId, accountLabel, plan, status, fetchedAt, windows, error }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? c.decode(String.self, forKey: .provider)) ?? "unknown"
        accountId = try? c.decode(String.self, forKey: .accountId)
        accountLabel = try? c.decode(String.self, forKey: .accountLabel)
        plan = try? c.decode(String.self, forKey: .plan)
        status = (try? c.decode(String.self, forKey: .status)) ?? "unavailable"
        windows = (try? c.decode([AccountQuotaWindow].self, forKey: .windows)) ?? []
        error = try? c.decode(String.self, forKey: .error)
        fetchedAt = usageTimestamp(try decoder.container(keyedBy: UsageDateKey.self), key: .fetchedAt)
    }
    public var providerName: String { provider == "claude" ? "Claude Code" : provider == "codex" ? "Codex" : provider.capitalized }
}

public struct AccountUsageResponse: Codable, Sendable {
    public var providers: [AccountUsageProvider]
    public init(providers: [AccountUsageProvider]) { self.providers = providers }
    private enum CodingKeys: String, CodingKey { case providers }
    public init(from decoder: Decoder) throws {
        providers = (try? decoder.container(keyedBy: CodingKeys.self).decode([AccountUsageProvider].self, forKey: .providers)) ?? []
    }
}

public struct AccountUsageHost: Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct AccountUsageHostSnapshot: Sendable {
    public var host: AccountUsageHost
    public var providers: [AccountUsageProvider]
    public var failed: Bool
    public var offline: Bool
    public init(host: AccountUsageHost, providers: [AccountUsageProvider], failed: Bool = false, offline: Bool = false) {
        self.host = host; self.providers = providers; self.failed = failed; self.offline = offline
    }
}

public struct AccountUsageCard: Sendable, Identifiable {
    public var id: String
    public var reading: AccountUsageProvider
    public var hosts: [AccountUsageHost]
    public var failed: Bool
    public var offline: Bool
    public var hostNames: String { hosts.map(\.label).joined(separator: ", ") }
    public var identityLine: String {
        if let label = reading.accountLabel, !label.isEmpty { return "\(label) · \(hostNames)" }
        return "\(hostNames) · account not identified"
    }
}

public enum AccountUsageTone: Sendable { case normal, high, critical, exhausted, unknown }
public struct AccountUsageRow: Sendable {
    public var title: String
    public var value: String
    public var percent: Double?
    public var subtitle: String
    public var tone: AccountUsageTone
}

public enum AccountUsagePresentation {
    public static func cards(_ snapshots: [AccountUsageHostSnapshot]) -> [AccountUsageCard] {
        struct Entry { var reading: AccountUsageProvider; var snapshot: AccountUsageHostSnapshot }
        var groups: [String: [Entry]] = [:]
        for snapshot in snapshots {
            for provider in snapshot.providers {
                let proof = provider.accountId.flatMap { $0.isEmpty ? nil : $0 }
                let key = "\(provider.provider):\(proof ?? "host:" + snapshot.host.id)"
                groups[key, default: []].append(Entry(reading: provider, snapshot: snapshot))
            }
        }
        var cards: [AccountUsageCard] = []
        for (key, entries) in groups {
            let sorted = entries.sorted {
                let aGood = !$0.snapshot.failed && $0.reading.status != "error"
                let bGood = !$1.snapshot.failed && $1.reading.status != "error"
                if aGood != bGood { return aGood }
                return ($0.reading.fetchedAt ?? 0) > ($1.reading.fetchedAt ?? 0)
            }
            let chosen = sorted[0]
            var hostsByID: [String: AccountUsageHost] = [:]
            for entry in entries { hostsByID[entry.snapshot.host.id] = entry.snapshot.host }
            let hosts = hostsByID.values.sorted { $0.label == $1.label ? $0.id < $1.id : $0.label < $1.label }
            cards.append(AccountUsageCard(id: key, reading: chosen.reading, hosts: hosts,
                                    failed: chosen.snapshot.failed || chosen.reading.status == "error",
                                    offline: entries.allSatisfy { $0.snapshot.offline }))
        }
        return cards.sorted {
            let a = $0.reading.provider == "claude" ? 0 : $0.reading.provider == "codex" ? 1 : 2
            let b = $1.reading.provider == "claude" ? 0 : $1.reading.provider == "codex" ? 1 : 2
            return a == b ? $0.id < $1.id : a < b
        }
    }

    public static func row(_ window: AccountQuotaWindow, now: Date = Date()) -> AccountUsageRow {
        let minutes = window.durationMinutes
        guard minutes.isFinite, minutes > 0, minutes <= 52_560_000 else {
            return AccountUsageRow(title: "Quota", value: "Not reported", percent: nil,
                                   subtitle: "The quota window wasn’t reported.", tone: .unknown)
        }
        let duration = minutes == 10080 ? "7 days" : minutes >= 60 && minutes.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(minutes / 60)) h" : "\(Int(max(0, minutes))) min"
        let base = minutes == 10080 ? "Weekly" : minutes < 10080 ? "Current window" : "Quota"
        // Missing rows are synthetic placeholders, not provider observations of
        // a duration. Keep the category without presenting an assumed length.
        let placeholder = window.id.hasPrefix("missing-") && window.usedPercent == nil
        let title = "\(base)\(window.name.map { " · \($0)" } ?? "")\(placeholder ? "" : " · " + duration)"
        guard let value = window.usedPercent, value.isFinite, value >= 0 else {
            return AccountUsageRow(title: title, value: "Not reported", percent: nil,
                                   subtitle: "This window wasn’t reported.", tone: .unknown)
        }
        let percent = min(100, value)
        let tone: AccountUsageTone = percent >= 100 ? .exhausted : percent >= 90 ? .critical : percent >= 75 ? .high : .normal
        var subtitle = tone == .exhausted ? "Used up · reset time not reported"
            : tone == .critical ? "Little left · reset time not reported" : "Reset time not reported"
        if let millis = window.resetsAt, millis.isFinite {
            let reset = Date(timeIntervalSince1970: millis / 1000)
            let formatter = DateFormatter()
            formatter.dateStyle = .none; formatter.timeStyle = .short
            let time = formatter.string(from: reset)
            if reset <= now { subtitle = "Reset \(time) · may already have reset" }
            else {
                let seconds = reset.timeIntervalSince(now)
                let relative: String
                if seconds >= 86400 { relative = "in \(max(1, Int(seconds / 86400))) d" }
                else if seconds >= 3600 { relative = "in \(Int(seconds / 3600)) h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)) m" }
                else { relative = "in \(max(1, Int(seconds / 60))) min" }
                if Calendar.current.isDate(reset, inSameDayAs: now) {
                    subtitle = "\(tone == .exhausted ? "Used up · back at" : "Resets") \(time) · \(relative)"
                } else {
                    formatter.dateFormat = "EEE, MMM d"
                    subtitle = "\(tone == .exhausted ? "Used up · back" : "Resets") \(formatter.string(from: reset)) · \(relative)"
                }
                if tone == .critical { subtitle = "Little left · \(subtitle.prefix(1).lowercased())\(subtitle.dropFirst())" }
            }
        }
        return AccountUsageRow(title: title, value: "\(Int(percent.rounded()))%", percent: percent, subtitle: subtitle, tone: tone)
    }

    public static func age(_ millis: Double?, now: Date) -> String {
        guard let millis, millis.isFinite else { return "No reading yet" }
        let elapsed = max(0, now.timeIntervalSince1970 - millis / 1000)
        if elapsed < 60 { return "Seen just now" }
        if elapsed < 3600 { return "Seen \(Int(elapsed / 60)) min ago" }
        if elapsed < 86400 { return "Seen \(Int(elapsed / 3600)) h ago" }
        return "Seen \(Int(elapsed / 86400)) d ago"
    }
    public static func stale(_ millis: Double?, now: Date) -> Bool {
        millis.map { now.timeIntervalSince1970 - $0 / 1000 > 300 } ?? false
    }
}

@MainActor @Observable
public final class AccountUsageStore {
    public private(set) var snapshots: [AccountUsageHostSnapshot] = []
    public private(set) var refreshing = false
    private var generation = UUID()
    public init() {}
    public var cards: [AccountUsageCard] { AccountUsagePresentation.cards(snapshots) }

    public func refresh(hosts: [AccountUsageHost], load: @escaping @Sendable (AccountUsageHost) async throws -> AccountUsageResponse) async {
        let request = UUID(); generation = request
        let keeping = Set(hosts.map(\.id))
        snapshots.removeAll { !keeping.contains($0.host.id) }
        refreshing = true
        defer { if generation == request { refreshing = false } }
        struct Fetched: Sendable { var host: AccountUsageHost; var response: AccountUsageResponse?; var offline: Bool; var cancelled: Bool }
        await withTaskGroup(of: Fetched.self) { group in
            for host in hosts {
                group.addTask {
                    do { return Fetched(host: host, response: try await load(host), offline: false, cancelled: false) }
                    catch {
                        let code = (error as? URLError)?.code
                        let offline = code.map { [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .timedOut, .dnsLookupFailed].contains($0) } ?? false
                        return Fetched(host: host, response: nil, offline: offline, cancelled: error is CancellationError || code == .cancelled)
                    }
                }
            }
            for await result in group {
                guard generation == request, !Task.isCancelled, !result.cancelled else { continue }
                let old = snapshots.first { $0.host.id == result.host.id }
                var providers: [AccountUsageProvider]
                if let response = result.response {
                    providers = response.providers.map { incoming in
                        guard incoming.status == "error", incoming.windows.isEmpty, let proof = incoming.accountId,
                              let previous = old?.providers.first(where: { $0.provider == incoming.provider && $0.accountId == proof }) else { return incoming }
                        var retained = previous; retained.status = "error"; retained.error = incoming.error
                        return retained
                    }
                    if providers.isEmpty { providers = ["claude", "codex"].map { AccountUsageProvider(provider: $0, status: "unavailable") } }
                } else {
                    providers = old?.providers ?? ["claude", "codex"].map { AccountUsageProvider(provider: $0, status: "error", error: "read_failed") }
                }
                let snapshot = AccountUsageHostSnapshot(host: result.host, providers: providers, failed: result.response == nil, offline: result.offline)
                if let index = snapshots.firstIndex(where: { $0.host.id == result.host.id }) { snapshots[index] = snapshot }
                else { snapshots.append(snapshot) }
            }
        }
    }
}

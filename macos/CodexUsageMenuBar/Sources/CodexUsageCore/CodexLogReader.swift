import Foundation

public final class CodexLogReader {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func readLatestSnapshot(sessionsDirectory: URL) -> UsageReadResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(UsageReadError(
                menuValue: "--",
                message: "No Codex session directory found",
                detail: sessionsDirectory.path
            ))
        }

        let files: [URL]
        do {
            files = try discoverSessionFiles(in: sessionsDirectory)
        } catch {
            return .failure(UsageReadError(
                menuValue: "!",
                message: "Unable to read Codex session logs",
                detail: "\(type(of: error)): \(error.localizedDescription)"
            ))
        }

        var firstReadError: String?
        for file in files {
            do {
                if let snapshot = try readLatestSnapshot(from: file) {
                    return .snapshot(snapshot)
                }
            } catch {
                if firstReadError == nil {
                    firstReadError = "\(file.path): \(type(of: error)): \(error.localizedDescription)"
                }
            }
        }

        if let firstReadError {
            return .failure(UsageReadError(
                menuValue: "!",
                message: "Unable to read Codex session logs",
                detail: firstReadError
            ))
        }

        return .failure(UsageReadError(
            menuValue: "--",
            message: "No rate limit event found yet. Open or use Codex once to generate usage data.",
            detail: nil
        ))
    }

    public func discoverSessionFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [(Date, URL)] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            candidates.append((values.contentModificationDate ?? .distantPast, fileURL))
        }
        return candidates.sorted { $0.0 > $1.0 }.map(\.1)
    }

    public func readLatestSnapshot(from fileURL: URL) throws -> UsageSnapshot? {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let record = try? decoder.decode(SessionRecord.self, from: data) else { continue }
            if let snapshot = makeSnapshot(from: record, sourcePath: fileURL.path) {
                return snapshot
            }
        }
        return nil
    }

    private func makeSnapshot(from record: SessionRecord, sourcePath: String) -> UsageSnapshot? {
        guard record.type == "event_msg",
              record.payload.type == "token_count",
              let rateLimits = record.payload.rateLimits
        else {
            return nil
        }

        let primary = makeWindow(rateLimits.primary)
        let secondary = makeWindow(rateLimits.secondary)
        guard primary != nil || secondary != nil else { return nil }

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            planType: rateLimits.planType,
            creditsDescription: creditsDescription(rateLimits.credits),
            reportedAt: parseTimestamp(record.timestamp),
            sourcePath: sourcePath
        )
    }

    private func makeWindow(_ raw: RateLimitWindow?) -> WindowUsage? {
        guard let raw else { return nil }
        return WindowUsage(
            label: UsageFormatting.windowLabel(minutes: raw.windowMinutes),
            usedPercent: raw.usedPercent,
            remainingPercent: UsageFormatting.remainingFromUsed(raw.usedPercent),
            resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func creditsDescription(_ credits: Credits?) -> String? {
        guard let credits else { return nil }
        if credits.unlimited == true { return "unlimited" }
        if let balance = credits.balance { return "\(balance)" }
        if credits.hasCredits == false { return "none" }
        if credits.hasCredits == true { return "available" }
        return nil
    }

    private func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct SessionRecord: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload
}

private struct Payload: Decodable {
    let type: String?
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct RateLimits: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: Credits?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case credits
        case planType = "plan_type"
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Double?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

private struct Credits: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: Int?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

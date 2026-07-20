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

        let files: [SessionFileCandidate]
        do {
            files = try discoverSessionFileCandidates(in: sessionsDirectory)
        } catch {
            return .failure(UsageReadError(
                menuValue: "!",
                message: "Unable to read Codex session logs",
                detail: "\(type(of: error)): \(error.localizedDescription)"
            ))
        }

        var firstReadError: String?
        var newestSnapshot: SnapshotCandidate?
        for file in files {
            do {
                for snapshot in try readSnapshotCandidates(from: file.url, fileModificationDate: file.modificationDate) {
                    if isNewer(snapshot, than: newestSnapshot) {
                        newestSnapshot = snapshot
                    }
                }
            } catch {
                if firstReadError == nil {
                    firstReadError = "\(file.url.path): \(type(of: error)): \(error.localizedDescription)"
                }
            }
        }

        if let newestSnapshot {
            return .snapshot(newestSnapshot.snapshot)
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
        try discoverSessionFileCandidates(in: directory).map(\.url)
    }

    private func discoverSessionFileCandidates(in directory: URL) throws -> [SessionFileCandidate] {
        guard fileManager.isReadableFile(atPath: directory.path) else {
            throw CodexLogReaderError.unreadableDirectory(directory.path)
        }

        var rootEnumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                if url.path == directory.path {
                    rootEnumerationError = error
                }
                return true
            }
        ) else {
            throw CodexLogReaderError.unableToEnumerateDirectory(directory.path)
        }

        var candidates: [(Date, URL)] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]) else {
                continue
            }
            guard values.isRegularFile == true else { continue }
            candidates.append((values.contentModificationDate ?? .distantPast, fileURL))
        }
        if let rootEnumerationError {
            throw CodexLogReaderError.enumerationFailed(directory.path, rootEnumerationError)
        }
        return candidates
            .sorted { $0.0 > $1.0 }
            .map { SessionFileCandidate(url: $0.1, modificationDate: $0.0) }
    }

    public func readLatestSnapshot(from fileURL: URL) throws -> UsageSnapshot? {
        let fileModificationDate = modificationDate(for: fileURL)
        var newestSnapshot: SnapshotCandidate?
        for snapshot in try readSnapshotCandidates(from: fileURL, fileModificationDate: fileModificationDate) {
            if isNewer(snapshot, than: newestSnapshot) {
                newestSnapshot = snapshot
            }
        }
        return newestSnapshot?.snapshot
    }

    private func readSnapshotCandidates(from fileURL: URL, fileModificationDate: Date) throws -> [SnapshotCandidate] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        var candidates: [SnapshotCandidate] = []
        for (sequence, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let record = try? decoder.decode(SessionRecord.self, from: data) else { continue }
            if let snapshot = makeSnapshot(from: record, sourcePath: fileURL.path) {
                candidates.append(SnapshotCandidate(
                    snapshot: snapshot,
                    isCanonicalCodexLimit: record.payload.rateLimits?.limitId == "codex",
                    sortDate: snapshot.reportedAt ?? fileModificationDate,
                    fileModificationDate: fileModificationDate,
                    sequence: sequence
                ))
            }
        }
        return candidates
    }

    private func modificationDate(for fileURL: URL) -> Date {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func isNewer(_ candidate: SnapshotCandidate, than current: SnapshotCandidate?) -> Bool {
        guard let current else { return true }
        if candidate.isCanonicalCodexLimit != current.isCanonicalCodexLimit {
            return candidate.isCanonicalCodexLimit
        }
        if candidate.sortDate != current.sortDate {
            return candidate.sortDate > current.sortDate
        }
        if candidate.fileModificationDate != current.fileModificationDate {
            return candidate.fileModificationDate > current.fileModificationDate
        }
        return candidate.sequence > current.sequence
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

private enum CodexLogReaderError: LocalizedError {
    case unreadableDirectory(String)
    case unableToEnumerateDirectory(String)
    case enumerationFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case let .unreadableDirectory(path):
            return "Directory is not readable: \(path)"
        case let .unableToEnumerateDirectory(path):
            return "Unable to enumerate directory: \(path)"
        case let .enumerationFailed(path, error):
            return "Unable to enumerate directory: \(path): \(error.localizedDescription)"
        }
    }
}

private struct SessionFileCandidate {
    let url: URL
    let modificationDate: Date
}

private struct SnapshotCandidate {
    let snapshot: UsageSnapshot
    let isCanonicalCodexLimit: Bool
    let sortDate: Date
    let fileModificationDate: Date
    let sequence: Int
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
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: Credits?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitId = "limit_id"
        case primary
        case secondary
        case credits
        case planType = "plan_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitId = try? container.decode(String.self, forKey: .limitId)
        primary = try? container.decode(RateLimitWindow.self, forKey: .primary)
        secondary = try? container.decode(RateLimitWindow.self, forKey: .secondary)
        credits = try? container.decode(Credits.self, forKey: .credits)
        planType = try? container.decode(String.self, forKey: .planType)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = container.decodeTolerantDouble(forKey: .usedPercent)
        windowMinutes = container.decodeTolerantDouble(forKey: .windowMinutes)
        resetsAt = container.decodeTolerantDouble(forKey: .resetsAt)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = container.decodeTolerantBool(forKey: .hasCredits)
        unlimited = container.decodeTolerantBool(forKey: .unlimited)
        balance = container.decodeTolerantInt(forKey: .balance)
    }
}

private extension KeyedDecodingContainer {
    func decodeTolerantBool(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            if value == 0 { return false }
            if value == 1 { return true }
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func decodeTolerantDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value.isFinite ? value : nil
        }
        if let value = try? decode(String.self, forKey: key) {
            guard let parsed = Double(value), parsed.isFinite else {
                return nil
            }
            return parsed
        }
        return nil
    }

    func decodeTolerantInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key),
           value.isFinite,
           value >= Double(Int.min),
           value < Double(Int.max)
        {
            return Int(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

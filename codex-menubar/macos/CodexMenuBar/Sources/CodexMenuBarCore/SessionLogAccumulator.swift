import Foundation

struct SessionLogAccumulator: Equatable, Sendable {
    private static let typeMarker = Data("\"type\"".utf8)
    private static let relevantRecordMarkers = [
        "\"session_meta\"",
        "\"user_message\"",
        "\"task_started\"",
        "\"task_complete\"",
        "\"token_count\""
    ].map { Data($0.utf8) }

    private let path: String
    private let maximumWarnings: Int
    private let maximumNameCharacters: Int
    private var workingDirectory: String?
    private var source: String?
    private var originator: String?
    private var threadSource: String?
    private var metadataTimestamp: Date?
    private var firstUserMessage: String?
    private var previousCumulative: TokenCounts?
    private var dailyCounts: [Date: TokenCounts] = [:]
    private var latestTokenCounts: TokenCounts = .zero
    private var latestRateLimit: RateLimitCandidate?
    private var lifecycle: LifecycleSummary = .inactive
    private var warnings: [ParseWarning] = []
    private var suppressedWarningCount = 0

    private(set) var sessionID: String?

    init(path: String, maximumWarnings: Int = 20, maximumNameCharacters: Int = 512) {
        precondition(maximumWarnings >= 0)
        precondition(maximumNameCharacters > 0)
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.maximumWarnings = maximumWarnings
        self.maximumNameCharacters = maximumNameCharacters
    }

    mutating func consume(
        record: JSONLRecord,
        modifiedAt: Date,
        cutoff: Date,
        today: Date,
        calendar: Calendar
    ) {
        if record.data.range(of: Self.typeMarker) != nil,
           !Self.relevantRecordMarkers.contains(where: { record.data.range(of: $0) != nil }) {
            return
        }

        guard let object = try? JSONSerialization.jsonObject(with: record.data) as? [String: Any] else {
            consume(warning: ParseWarning(path: path, line: record.lineNumber, message: "Malformed JSON record"))
            return
        }

        let recordTimestamp = string(object["timestamp"]).flatMap(parseTimestamp)
        let recordType = string(object["type"])
        let payload = object["payload"] as? [String: Any]

        if recordType == "session_meta", let payload {
            sessionID = string(payload["session_id"]) ?? string(payload["id"]) ?? sessionID
            workingDirectory = string(payload["cwd"]) ?? workingDirectory
            source = string(payload["source"]) ?? source
            originator = string(payload["originator"]) ?? originator
            threadSource = string(payload["thread_source"]) ?? threadSource
            metadataTimestamp = string(payload["timestamp"]).flatMap(parseTimestamp)
                ?? recordTimestamp
                ?? metadataTimestamp
        }

        guard recordType == "event_msg", let payload else { return }
        switch string(payload["type"]) {
        case "user_message":
            if firstUserMessage == nil {
                let message = boundedName(string(payload["message"]) ?? string(payload["text"]) ?? "")
                if !message.isEmpty { firstUserMessage = message }
            }
        case "task_started":
            lifecycle = .active
        case "task_complete":
            lifecycle = .inactive
        case "token_count":
            if let timestamp = recordTimestamp,
               let info = payload["info"] as? [String: Any],
               let totalUsage = info["total_token_usage"] as? [String: Any] {
                let current = tokenCounts(from: totalUsage)
                let increment = current.increment(since: previousCumulative)
                previousCumulative = current
                latestTokenCounts = current
                let day = calendar.startOfDay(for: timestamp)
                if day >= cutoff, day <= today {
                    dailyCounts[day, default: .zero] = dailyCounts[day, default: .zero] + increment
                }
                prune(cutoff: cutoff, today: today)
            }
            if let rawLimits = payload["rate_limits"] as? [String: Any] {
                let candidate = RateLimitCandidate(
                    limitID: string(rawLimits["limit_id"]),
                    primary: rawWindow(rawLimits["primary"]),
                    secondary: rawWindow(rawLimits["secondary"]),
                    credits: rawCredits(rawLimits["credits"]),
                    planType: string(rawLimits["plan_type"]),
                    reportedAt: recordTimestamp,
                    fileModifiedAt: modifiedAt,
                    sequence: record.lineNumber - 1,
                    sourcePath: path
                )
                if RateLimitCandidateOrdering.isNewer(candidate, than: latestRateLimit) {
                    latestRateLimit = candidate
                }
            }
        default:
            break
        }
    }

    mutating func consume(warning: ParseWarning) {
        if warnings.count < maximumWarnings {
            warnings.append(warning)
        } else {
            suppressedWarningCount += 1
        }
    }

    mutating func prune(cutoff: Date, today: Date) {
        dailyCounts = dailyCounts.filter { $0.key >= cutoff && $0.key <= today }
    }

    func summary(modifiedAt: Date, threadName: String?) -> SessionLogSummary {
        let stableID = sessionID ?? path
        let directoryName = workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
        let fullName = [threadName, firstUserMessage, directoryName]
            .compactMap { $0 }
            .map(boundedName)
            .first(where: { !$0.isEmpty })
            ?? "Untitled session"
        let rateLimit = latestRateLimit.map { candidate in
            RateLimitCandidate(
                limitID: candidate.limitID,
                primary: candidate.primary,
                secondary: candidate.secondary,
                credits: candidate.credits,
                planType: candidate.planType,
                reportedAt: candidate.reportedAt,
                fileModifiedAt: modifiedAt,
                sequence: candidate.sequence,
                sourcePath: candidate.sourcePath
            )
        }

        return SessionLogSummary(
            path: path,
            modifiedAt: modifiedAt,
            session: SessionIdentity(
                id: stableID,
                name: fullName,
                displayName: SessionTextFormatting.displayDescription(fullName),
                workingDirectory: workingDirectory,
                sourceKind: sourceKind(source: source, originator: originator, threadSource: threadSource)
            ),
            metadataTimestamp: metadataTimestamp,
            dailyCounts: dailyCounts,
            latestTokenCounts: latestTokenCounts,
            latestRateLimit: rateLimit,
            lifecycle: lifecycle,
            warnings: warnings,
            suppressedWarningCount: suppressedWarningCount,
            isTopLevelInteractiveTUI: source == "cli" && originator == "codex-tui" && threadSource == "user"
        )
    }

    private func boundedName(_ value: String) -> String {
        String(SessionTextFormatting.normalized(value).prefix(maximumNameCharacters))
    }

    private func tokenCounts(from object: [String: Any]) -> TokenCounts {
        TokenCounts(
            total: nonnegativeInt64(object["total_tokens"]),
            input: nonnegativeInt64(object["input_tokens"]),
            cachedInput: nonnegativeInt64(object["cached_input_tokens"]),
            output: nonnegativeInt64(object["output_tokens"]),
            reasoning: nonnegativeInt64(object["reasoning_output_tokens"])
        )
    }

    private func rawWindow(_ value: Any?) -> RawRateLimitWindow? {
        guard let object = value as? [String: Any] else { return nil }
        return RawRateLimitWindow(
            usedPercent: finiteDouble(object["used_percent"]),
            windowMinutes: finiteDouble(object["window_minutes"]),
            resetsAt: finiteDouble(object["resets_at"])
        )
    }

    private func rawCredits(_ value: Any?) -> RawCredits? {
        guard let object = value as? [String: Any] else { return nil }
        return RawCredits(
            hasCredits: tolerantBool(object["has_credits"]),
            unlimited: tolerantBool(object["unlimited"]),
            balance: tolerantInt(object["balance"])
        )
    }

    private func sourceKind(source: String?, originator: String?, threadSource: String?) -> String {
        let values = [source, originator, threadSource]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if values.contains("codex-tui") || source?.lowercased() == "cli" { return "cli" }
        if values.contains("exec") { return "exec" }
        if values.contains("review") { return "review" }
        if values.contains("codex desktop") || values.contains("chatgpt") { return "App" }
        if values.contains("vscode") || values.contains("ide") { return "IDE" }
        if values.contains("app") { return "App" }
        return "Other"
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func nonnegativeInt64(_ value: Any?) -> Int64 {
        guard let parsed = finiteDouble(value), parsed >= 0, parsed < 9_223_372_036_854_775_808.0 else {
            return 0
        }
        return Int64(parsed)
    }

    private func finiteDouble(_ value: Any?) -> Double? {
        let parsed: Double?
        if let number = value as? NSNumber {
            parsed = number.doubleValue
        } else if let string = value as? String {
            parsed = Double(string)
        } else {
            parsed = nil
        }
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
    }

    private func tolerantBool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber {
            if number.intValue == 0 { return false }
            if number.intValue == 1 { return true }
        }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private func tolerantInt(_ value: Any?) -> Int? {
        guard let parsed = finiteDouble(value), parsed >= Double(Int.min), parsed < Double(Int.max) else {
            return nil
        }
        return Int(parsed)
    }
}

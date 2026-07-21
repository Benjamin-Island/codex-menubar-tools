import Foundation

public final class CodexLogParser: @unchecked Sendable {
    private static let typeMarker = Data("\"type\"".utf8)
    private static let newline = Data([0x0A])
    private static let relevantRecordMarkers = [
        "\"session_meta\"",
        "\"user_message\"",
        "\"task_started\"",
        "\"task_complete\"",
        "\"token_count\""
    ].map { Data($0.utf8) }

    public init() {}

    public func parse(
        logURL: URL,
        sessionNames: [String: String],
        modifiedAt: Date
    ) throws -> IndexedSessionLog {
        let contents = try Data(contentsOf: logURL, options: .mappedIfSafe)
        var warnings: [ParseWarning] = []
        var sessionID: String?
        var workingDirectory: String?
        var source: String?
        var originator: String?
        var threadSource: String?
        var metadataTimestamp: Date?
        var firstUserMessage: String?
        var tokenEvents: [TokenEvent] = []
        var rateLimits: [RateLimitCandidate] = []
        var lifecycle: LifecycleSummary = .inactive

        var lineStart = 0
        var lineNumber = 1
        while lineStart <= contents.count {
            let newlineRange = lineStart < contents.count
                ? contents.range(of: Self.newline, in: lineStart..<contents.count)
                : nil
            let lineEnd = newlineRange?.lowerBound ?? contents.count
            let lineRange = lineStart..<lineEnd
            defer {
                if let newlineRange {
                    lineStart = newlineRange.upperBound
                    lineNumber += 1
                } else {
                    lineStart = contents.count + 1
                }
            }
            guard !lineRange.isEmpty else { continue }
            if contents.range(of: Self.typeMarker, in: lineRange) != nil,
               !Self.relevantRecordMarkers.contains(where: {
                   contents.range(of: $0, in: lineRange) != nil
               })
            {
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(
                with: contents.subdata(in: lineRange)
            ) as? [String: Any]
            else {
                warnings.append(ParseWarning(
                    path: logURL.path,
                    line: lineNumber,
                    message: "Malformed JSON record"
                ))
                continue
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

            guard recordType == "event_msg", let payload else { continue }
            switch string(payload["type"]) {
            case "user_message":
                if firstUserMessage == nil {
                    let message = normalize(string(payload["message"]) ?? string(payload["text"]) ?? "")
                    if !message.isEmpty { firstUserMessage = message }
                }
            case "task_started":
                lifecycle = .active
            case "task_complete":
                lifecycle = .inactive
            case "token_count":
                if let timestamp = recordTimestamp,
                   let info = payload["info"] as? [String: Any],
                   let totalUsage = info["total_token_usage"] as? [String: Any]
                {
                    tokenEvents.append(TokenEvent(
                        timestamp: timestamp,
                        cumulative: tokenCounts(from: totalUsage),
                        sequence: lineNumber - 1
                    ))
                }
                if let rawLimits = payload["rate_limits"] as? [String: Any] {
                    rateLimits.append(RateLimitCandidate(
                        limitID: string(rawLimits["limit_id"]),
                        primary: rawWindow(rawLimits["primary"]),
                        secondary: rawWindow(rawLimits["secondary"]),
                        credits: rawCredits(rawLimits["credits"]),
                        planType: string(rawLimits["plan_type"]),
                        reportedAt: recordTimestamp,
                        fileModifiedAt: modifiedAt,
                        sequence: lineNumber - 1,
                        sourcePath: logURL.path
                    ))
                }
            default:
                continue
            }
        }

        let stableID = sessionID ?? logURL.standardizedFileURL.path
        let directoryName = workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
        let fullName = sessionNames[stableID]
            ?? firstUserMessage
            ?? directoryName.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Untitled session"

        return IndexedSessionLog(
            path: logURL.standardizedFileURL.path,
            modifiedAt: modifiedAt,
            session: SessionIdentity(
                id: stableID,
                name: fullName,
                displayName: String(fullName.prefix(60)),
                workingDirectory: workingDirectory,
                sourceKind: sourceKind(source: source, originator: originator, threadSource: threadSource)
            ),
            metadataTimestamp: metadataTimestamp,
            tokenEvents: tokenEvents,
            rateLimits: rateLimits,
            lifecycle: lifecycle,
            warnings: warnings,
            isTopLevelInteractiveTUI: source == "cli"
                && originator == "codex-tui"
                && threadSource == "user"
        )
    }

    public func readSessionNames(at indexURL: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [:] }
        let contents = try String(contentsOf: indexURL, encoding: .utf8)
        var names: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = string(object["id"]),
                  let rawName = string(object["thread_name"])
            else {
                continue
            }
            let name = normalize(rawName)
            if !name.isEmpty { names[id] = name }
        }
        return names
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
        if values.contains("vscode") || values.contains("ide") { return "IDE" }
        if values.contains("chatgpt") || values.contains("app") { return "App" }
        return "Other"
    }

    private func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
        guard let parsed = finiteDouble(value),
              parsed >= 0,
              parsed < 9_223_372_036_854_775_808.0
        else {
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
        guard let parsed = finiteDouble(value),
              parsed >= Double(Int.min),
              parsed <= Double(Int.max)
        else {
            return nil
        }
        return Int(parsed)
    }
}

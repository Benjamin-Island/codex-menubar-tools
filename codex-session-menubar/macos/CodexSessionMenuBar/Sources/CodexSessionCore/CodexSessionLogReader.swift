import Foundation

public final class CodexSessionLogReader: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func readSessionNames(at indexURL: URL) throws -> [String: String] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [:] }

        var names: [String: String] = [:]
        for object in try readJSONLines(at: indexURL) {
            guard let id = object["id"] as? String,
                  let rawName = object["thread_name"] as? String
            else {
                continue
            }
            let name = SessionTextFormatting.normalized(rawName)
            if !name.isEmpty {
                names[id] = name
            }
        }
        return names
    }

    public func readSession(
        at logURL: URL,
        sessionNames: [String: String],
        modifiedAt: Date,
        now: Date
    ) throws -> SessionLogSnapshot? {
        let objects = try readJSONLines(at: logURL)
        guard let metadata = metadata(from: objects), metadata.isTopLevelInteractiveTUI else {
            return nil
        }

        var firstUserMessage: String?
        var taskIsActive = false
        for object in objects {
            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String
            else {
                continue
            }

            switch payloadType {
            case "user_message":
                if firstUserMessage == nil {
                    let rawMessage = (payload["message"] as? String) ?? (payload["text"] as? String)
                    if let rawMessage {
                        let message = SessionTextFormatting.normalized(rawMessage)
                        if !message.isEmpty {
                            firstUserMessage = message
                        }
                    }
                }
            case "task_started":
                taskIsActive = true
            case "task_complete":
                taskIsActive = false
            default:
                continue
            }
        }

        let directoryFallback = URL(fileURLWithPath: metadata.workingDirectory).lastPathComponent
        let taskDescription = sessionNames[metadata.sessionID]
            ?? firstUserMessage
            ?? directoryFallback
        let activity: SessionActivity = taskIsActive && now.timeIntervalSince(modifiedAt) < 300
            ? .running
            : .stalled

        return SessionLogSnapshot(
            sessionID: metadata.sessionID,
            workingDirectory: metadata.workingDirectory,
            taskDescription: taskDescription,
            displayTaskDescription: SessionTextFormatting.displayDescription(taskDescription),
            activity: activity,
            sourcePath: logURL.path,
            metadataTimestamp: metadata.timestamp
        )
    }

    public func readMetadata(at logURL: URL) throws -> SessionMetadata? {
        metadata(from: try readJSONLines(at: logURL))
    }

    private func metadata(from objects: [[String: Any]]) -> SessionMetadata? {
        for object in objects where object["type"] as? String == "session_meta" {
            guard let payload = object["payload"] as? [String: Any],
                  let sessionID = (payload["session_id"] as? String) ?? (payload["id"] as? String),
                  let cwd = payload["cwd"] as? String,
                  let source = payload["source"] as? String,
                  let originator = payload["originator"] as? String,
                  let threadSource = payload["thread_source"] as? String,
                  let timestampValue = (payload["timestamp"] as? String) ?? (object["timestamp"] as? String),
                  let timestamp = parseTimestamp(timestampValue)
            else {
                continue
            }

            return SessionMetadata(
                sessionID: sessionID,
                timestamp: timestamp,
                workingDirectory: cwd,
                source: source,
                originator: originator,
                threadSource: threadSource
            )
        }
        return nil
    }

    private func readJSONLines(at url: URL) throws -> [[String: Any]] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    return nil
                }
                return object
            }
    }

    private func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

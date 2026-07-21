import Foundation

public enum SessionActivity: String, Equatable, Sendable {
    case running
    case stalled
}

public struct ProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let userID: UInt32
    public let startedAt: Date
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let hasControllingTerminal: Bool
    public let openFilePaths: [String]

    public init(
        pid: Int32,
        parentPID: Int32,
        userID: UInt32,
        startedAt: Date,
        executablePath: String,
        arguments: [String],
        workingDirectory: String?,
        hasControllingTerminal: Bool,
        openFilePaths: [String]
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.userID = userID
        self.startedAt = startedAt
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.hasControllingTerminal = hasControllingTerminal
        self.openFilePaths = openFilePaths
    }
}

public protocol ProcessProviding: Sendable {
    func processSnapshots() throws -> [ProcessSnapshot]
}

public struct SessionDisplaySnapshot: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let sessionID: String?
    public let activity: SessionActivity
    public let taskDescription: String
    public let displayTaskDescription: String
    public let workingDirectory: String
    public let sourcePath: String?
    public let lastUpdatedAt: Date?
    public let tokenCounts: TokenCounts

    public init(
        pid: Int32,
        sessionID: String?,
        activity: SessionActivity,
        taskDescription: String,
        displayTaskDescription: String,
        workingDirectory: String,
        sourcePath: String?,
        lastUpdatedAt: Date?,
        tokenCounts: TokenCounts
    ) {
        self.pid = pid
        self.sessionID = sessionID
        self.activity = activity
        self.taskDescription = taskDescription
        self.displayTaskDescription = displayTaskDescription
        self.workingDirectory = workingDirectory
        self.sourcePath = sourcePath
        self.lastUpdatedAt = lastUpdatedAt
        self.tokenCounts = tokenCounts
    }
}

public struct SessionInventoryError: Error, Equatable, Sendable {
    public let message: String
    public let detail: String?

    public init(message: String, detail: String?) {
        self.message = message
        self.detail = detail
    }
}

public enum SessionInventoryResult: Equatable, Sendable {
    case snapshots([SessionDisplaySnapshot])
    case failure(SessionInventoryError)
}

public enum SessionTextFormatting {
    public static func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func displayDescription(_ value: String) -> String {
        String(normalized(value).prefix(60))
    }
}

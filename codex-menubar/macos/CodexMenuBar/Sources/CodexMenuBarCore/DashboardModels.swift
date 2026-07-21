import Foundation

public enum ContentState<Value: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case content(Value)
    case empty(String)
    case failure(DashboardError)
}

public struct DashboardError: Error, Equatable, Sendable {
    public let message: String
    public let detail: String?

    public init(message: String, detail: String?) {
        self.message = message
        self.detail = detail
    }
}

public struct DashboardWarning: Equatable, Sendable {
    public let path: String
    public let line: Int
    public let message: String

    public init(path: String, line: Int, message: String) {
        self.path = path
        self.line = line
        self.message = message
    }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public let rateLimit: ContentState<UsageSnapshot>
    public let history: ContentState<TokenHistorySnapshot>
    public let sessions: ContentState<[SessionDisplaySnapshot]>
    public let warnings: [DashboardWarning]
    public let updatedAt: Date

    public init(
        rateLimit: ContentState<UsageSnapshot>,
        history: ContentState<TokenHistorySnapshot>,
        sessions: ContentState<[SessionDisplaySnapshot]>,
        warnings: [DashboardWarning],
        updatedAt: Date
    ) {
        self.rateLimit = rateLimit
        self.history = history
        self.sessions = sessions
        self.warnings = warnings
        self.updatedAt = updatedAt
    }

    public static func loading(at date: Date = Date()) -> DashboardSnapshot {
        DashboardSnapshot(
            rateLimit: .loading,
            history: .loading,
            sessions: .loading,
            warnings: [],
            updatedAt: date
        )
    }
}

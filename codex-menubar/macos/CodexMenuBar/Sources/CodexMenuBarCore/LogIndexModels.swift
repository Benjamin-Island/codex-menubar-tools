import Foundation

public enum LifecycleSummary: Equatable, Sendable {
    case active
    case inactive
}

public struct ParseWarning: Equatable, Sendable {
    public let path: String
    public let line: Int
    public let message: String

    public init(path: String, line: Int, message: String) {
        self.path = path
        self.line = line
        self.message = message
    }
}

public struct RawRateLimitWindow: Equatable, Sendable {
    public let usedPercent: Double?
    public let windowMinutes: Double?
    public let resetsAt: Double?

    public init(usedPercent: Double?, windowMinutes: Double?, resetsAt: Double?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct RawCredits: Equatable, Sendable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: Int?

    public init(hasCredits: Bool?, unlimited: Bool?, balance: Int?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

public struct RateLimitCandidate: Equatable, Sendable {
    public let limitID: String?
    public let primary: RawRateLimitWindow?
    public let secondary: RawRateLimitWindow?
    public let credits: RawCredits?
    public let planType: String?
    public let reportedAt: Date?
    public let fileModifiedAt: Date
    public let sequence: Int
    public let sourcePath: String

    public init(
        limitID: String?,
        primary: RawRateLimitWindow?,
        secondary: RawRateLimitWindow?,
        credits: RawCredits?,
        planType: String?,
        reportedAt: Date?,
        fileModifiedAt: Date,
        sequence: Int,
        sourcePath: String
    ) {
        self.limitID = limitID
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.reportedAt = reportedAt
        self.fileModifiedAt = fileModifiedAt
        self.sequence = sequence
        self.sourcePath = sourcePath
    }
}

public struct IndexedSessionLog: Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let session: SessionIdentity
    public let metadataTimestamp: Date?
    public let tokenEvents: [TokenEvent]
    public let rateLimits: [RateLimitCandidate]
    public let lifecycle: LifecycleSummary
    public let warnings: [ParseWarning]
    public let isTopLevelInteractiveTUI: Bool

    public init(
        path: String,
        modifiedAt: Date,
        session: SessionIdentity,
        metadataTimestamp: Date?,
        tokenEvents: [TokenEvent],
        rateLimits: [RateLimitCandidate],
        lifecycle: LifecycleSummary,
        warnings: [ParseWarning],
        isTopLevelInteractiveTUI: Bool = false
    ) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.session = session
        self.metadataTimestamp = metadataTimestamp
        self.tokenEvents = tokenEvents
        self.rateLimits = rateLimits
        self.lifecycle = lifecycle
        self.warnings = warnings
        self.isTopLevelInteractiveTUI = isTopLevelInteractiveTUI
    }
}

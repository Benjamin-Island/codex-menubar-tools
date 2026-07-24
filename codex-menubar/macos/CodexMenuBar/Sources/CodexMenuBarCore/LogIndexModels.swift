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

public struct DailyRateLimitWindowObservation: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Double?
    public let reportedAt: Date
    public let sequence: Int
    public let sourcePath: String

    public init(
        usedPercent: Double,
        resetsAt: Double?,
        reportedAt: Date,
        sequence: Int,
        sourcePath: String
    ) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.reportedAt = reportedAt
        self.sequence = sequence
        self.sourcePath = sourcePath
    }
}

public struct DailyRateLimitWindowTrace: Equatable, Sendable {
    public let first: DailyRateLimitWindowObservation
    public let last: DailyRateLimitWindowObservation
    public let didReset: Bool

    public init(
        first: DailyRateLimitWindowObservation,
        last: DailyRateLimitWindowObservation,
        didReset: Bool
    ) {
        self.first = first
        self.last = last
        self.didReset = didReset
    }
}

public struct DailyRateLimitFamilyTrace: Equatable, Sendable {
    public let primary: DailyRateLimitWindowTrace?
    public let secondary: DailyRateLimitWindowTrace?

    public init(
        primary: DailyRateLimitWindowTrace?,
        secondary: DailyRateLimitWindowTrace?
    ) {
        self.primary = primary
        self.secondary = secondary
    }
}

public struct DailyRateLimitTrace: Equatable, Sendable {
    public let day: Date
    public let canonical: DailyRateLimitFamilyTrace?
    public let fallback: DailyRateLimitFamilyTrace?

    public init(
        day: Date,
        canonical: DailyRateLimitFamilyTrace?,
        fallback: DailyRateLimitFamilyTrace?
    ) {
        self.day = day
        self.canonical = canonical
        self.fallback = fallback
    }
}

public struct SessionLogSummary: Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let session: SessionIdentity
    public let metadataTimestamp: Date?
    public let dailyCounts: [Date: TokenCounts]
    public let latestTokenCounts: TokenCounts
    public let latestRateLimit: RateLimitCandidate?
    public let dailyRateLimitTrace: DailyRateLimitTrace?
    public let lifecycle: LifecycleSummary
    public let warnings: [ParseWarning]
    public let suppressedWarningCount: Int
    public let isTopLevelLiveSession: Bool

    public init(
        path: String,
        modifiedAt: Date,
        session: SessionIdentity,
        metadataTimestamp: Date?,
        dailyCounts: [Date: TokenCounts],
        latestTokenCounts: TokenCounts,
        latestRateLimit: RateLimitCandidate?,
        dailyRateLimitTrace: DailyRateLimitTrace? = nil,
        lifecycle: LifecycleSummary,
        warnings: [ParseWarning],
        suppressedWarningCount: Int,
        isTopLevelLiveSession: Bool
    ) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.session = session
        self.metadataTimestamp = metadataTimestamp
        self.dailyCounts = dailyCounts
        self.latestTokenCounts = latestTokenCounts
        self.latestRateLimit = latestRateLimit
        self.dailyRateLimitTrace = dailyRateLimitTrace
        self.lifecycle = lifecycle
        self.warnings = warnings
        self.suppressedWarningCount = suppressedWarningCount
        self.isTopLevelLiveSession = isTopLevelLiveSession
    }
}

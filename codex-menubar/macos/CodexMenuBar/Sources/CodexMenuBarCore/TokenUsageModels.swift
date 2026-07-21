import Foundation

public struct TokenCounts: Equatable, Sendable, Codable {
    public let total: Int64
    public let input: Int64
    public let cachedInput: Int64
    public let output: Int64
    public let reasoning: Int64

    public init(
        total: Int64,
        input: Int64,
        cachedInput: Int64,
        output: Int64,
        reasoning: Int64
    ) {
        self.total = total
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.reasoning = reasoning
    }

    public static let zero = TokenCounts(
        total: 0,
        input: 0,
        cachedInput: 0,
        output: 0,
        reasoning: 0
    )

    public func increment(since previous: TokenCounts?) -> TokenCounts {
        func delta(_ current: Int64, _ old: Int64?) -> Int64 {
            guard let old, current >= old else { return max(0, current) }
            return current - old
        }

        return TokenCounts(
            total: delta(total, previous?.total),
            input: delta(input, previous?.input),
            cachedInput: delta(cachedInput, previous?.cachedInput),
            output: delta(output, previous?.output),
            reasoning: delta(reasoning, previous?.reasoning)
        )
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            total: lhs.total + rhs.total,
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }
}

public struct SessionIdentity: Hashable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let workingDirectory: String?
    public let sourceKind: String

    public init(
        id: String,
        name: String,
        displayName: String,
        workingDirectory: String?,
        sourceKind: String
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.workingDirectory = workingDirectory
        self.sourceKind = sourceKind
    }
}

public struct SessionDayUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let session: SessionIdentity
    public let counts: TokenCounts

    public init(id: String, session: SessionIdentity, counts: TokenCounts) {
        self.id = id
        self.session = session
        self.counts = counts
    }
}

public struct DailyUsage: Identifiable, Equatable, Sendable {
    public let id: Date
    public let date: Date
    public let counts: TokenCounts
    public let sessions: [SessionDayUsage]
    public let heatLevel: Int
    public let isFuture: Bool

    public init(
        date: Date,
        counts: TokenCounts,
        sessions: [SessionDayUsage],
        heatLevel: Int,
        isFuture: Bool
    ) {
        id = date
        self.date = date
        self.counts = counts
        self.sessions = sessions
        self.heatLevel = heatLevel
        self.isFuture = isFuture
    }
}

public struct HeatmapDay: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let usage: DailyUsage?

    public init(date: Date, usage: DailyUsage?) {
        self.date = date
        self.usage = usage
    }
}

public struct TokenHistorySnapshot: Equatable, Sendable {
    public let interval: DateInterval
    public let days: [DailyUsage]
    public let heatmapDays: [HeatmapDay]
    public let selectedDefaultDate: Date

    public init(
        interval: DateInterval,
        days: [DailyUsage],
        heatmapDays: [HeatmapDay],
        selectedDefaultDate: Date
    ) {
        self.interval = interval
        self.days = days
        self.heatmapDays = heatmapDays
        self.selectedDefaultDate = selectedDefaultDate
    }
}

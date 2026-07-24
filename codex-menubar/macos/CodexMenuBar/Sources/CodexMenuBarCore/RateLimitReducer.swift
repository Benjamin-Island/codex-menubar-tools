import Foundation

public struct RateLimitReducer: Sendable {
    public init() {}

    public func reduce(
        summaries: [SessionLogSummary],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> UsageReadResult {
        var newest: RateLimitCandidate?
        for candidate in summaries.compactMap(\.latestRateLimit)
            where candidate.primary != nil || candidate.secondary != nil {
            if RateLimitCandidateOrdering.isNewer(candidate, than: newest) {
                newest = candidate
            }
        }

        guard let newest else {
            return .failure(UsageReadError(
                menuValue: "--",
                message: "No rate limit event found yet. Open or use Codex once to generate usage data.",
                detail: nil
            ))
        }

        let dailyTraces = dailyWindowTraces(
            summaries: summaries,
            useCanonicalFamily: newest.limitID == "codex",
            calendar: calendar,
            now: now
        )

        return .snapshot(UsageSnapshot(
            primary: makeWindow(newest.primary, dailyTraces: dailyTraces.primary),
            secondary: makeWindow(newest.secondary, dailyTraces: dailyTraces.secondary),
            planType: newest.planType,
            creditsDescription: creditsDescription(newest.credits),
            reportedAt: newest.reportedAt,
            sourcePath: newest.sourcePath
        ))
    }

    private func makeWindow(
        _ raw: RawRateLimitWindow?,
        dailyTraces: [DailyRateLimitWindowTrace]
    ) -> WindowUsage? {
        guard let raw else { return nil }
        let daily = aggregate(dailyTraces)
        return WindowUsage(
            label: UsageFormatting.windowLabel(minutes: raw.windowMinutes),
            usedPercent: raw.usedPercent,
            remainingPercent: UsageFormatting.remainingFromUsed(raw.usedPercent),
            resetsAt: raw.resetsAt.map(Date.init(timeIntervalSince1970:)),
            todayInitialRemainingPercent: UsageFormatting.remainingFromUsed(daily?.first.usedPercent),
            didResetToday: daily?.didReset ?? false
        )
    }

    private func dailyWindowTraces(
        summaries: [SessionLogSummary],
        useCanonicalFamily: Bool,
        calendar: Calendar,
        now: Date
    ) -> (
        primary: [DailyRateLimitWindowTrace],
        secondary: [DailyRateLimitWindowTrace]
    ) {
        var primary: [DailyRateLimitWindowTrace] = []
        var secondary: [DailyRateLimitWindowTrace] = []

        for summary in summaries {
            guard let trace = summary.dailyRateLimitTrace,
                  calendar.isDate(trace.day, inSameDayAs: now)
            else {
                continue
            }
            let family = useCanonicalFamily ? trace.canonical : trace.fallback
            if let window = family?.primary {
                primary.append(window)
            }
            if let window = family?.secondary {
                secondary.append(window)
            }
        }

        return (primary, secondary)
    }

    private func aggregate(
        _ traces: [DailyRateLimitWindowTrace]
    ) -> (first: DailyRateLimitWindowObservation, didReset: Bool)? {
        guard let first = traces.map(\.first).min(by: observationIsEarlier) else {
            return nil
        }
        let resetValues = Set(
            traces.flatMap { [$0.first.resetsAt, $0.last.resetsAt] }.compactMap { $0 }
        )
        return (
            first,
            traces.contains(where: \.didReset) || resetValues.count > 1
        )
    }

    private func observationIsEarlier(
        _ lhs: DailyRateLimitWindowObservation,
        _ rhs: DailyRateLimitWindowObservation
    ) -> Bool {
        if lhs.reportedAt != rhs.reportedAt {
            return lhs.reportedAt < rhs.reportedAt
        }
        if lhs.sourcePath != rhs.sourcePath {
            return lhs.sourcePath < rhs.sourcePath
        }
        return lhs.sequence < rhs.sequence
    }

    private func creditsDescription(_ credits: RawCredits?) -> String? {
        guard let credits else { return nil }
        if credits.unlimited == true { return "unlimited" }
        if let balance = credits.balance { return "\(balance)" }
        if credits.hasCredits == false { return "none" }
        if credits.hasCredits == true { return "available" }
        return nil
    }
}

enum RateLimitCandidateOrdering {
    static func isNewer(_ lhs: RateLimitCandidate, than rhs: RateLimitCandidate?) -> Bool {
        guard let rhs else { return true }
        let lhsCanonical = lhs.limitID == "codex"
        let rhsCanonical = rhs.limitID == "codex"
        if lhsCanonical != rhsCanonical { return lhsCanonical }
        let lhsDate = lhs.reportedAt ?? lhs.fileModifiedAt
        let rhsDate = rhs.reportedAt ?? rhs.fileModifiedAt
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt > rhs.fileModifiedAt }
        return lhs.sequence > rhs.sequence
    }
}

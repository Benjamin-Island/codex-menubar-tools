import Foundation

public struct RateLimitReducer: Sendable {
    public init() {}

    public func reduce(logs: [IndexedSessionLog]) -> UsageReadResult {
        var newest: RateLimitCandidate?
        for candidate in logs.flatMap(\.rateLimits) where candidate.primary != nil || candidate.secondary != nil {
            if isNewer(candidate, than: newest) {
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

        return .snapshot(UsageSnapshot(
            primary: makeWindow(newest.primary),
            secondary: makeWindow(newest.secondary),
            planType: newest.planType,
            creditsDescription: creditsDescription(newest.credits),
            reportedAt: newest.reportedAt,
            sourcePath: newest.sourcePath
        ))
    }

    private func isNewer(_ lhs: RateLimitCandidate, than rhs: RateLimitCandidate?) -> Bool {
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

    private func makeWindow(_ raw: RawRateLimitWindow?) -> WindowUsage? {
        guard let raw else { return nil }
        return WindowUsage(
            label: UsageFormatting.windowLabel(minutes: raw.windowMinutes),
            usedPercent: raw.usedPercent,
            remainingPercent: UsageFormatting.remainingFromUsed(raw.usedPercent),
            resetsAt: raw.resetsAt.map(Date.init(timeIntervalSince1970:))
        )
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

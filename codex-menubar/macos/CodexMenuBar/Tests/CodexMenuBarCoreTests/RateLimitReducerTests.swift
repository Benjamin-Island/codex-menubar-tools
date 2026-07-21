import XCTest
@testable import CodexMenuBarCore

final class RateLimitReducerTests: XCTestCase {
    func testBuildsPrimarySecondaryPlanAndCredits() throws {
        let result = RateLimitReducer().reduce(summaries: [log(
            path: "/a.jsonl",
            candidates: [candidate(
                usedPrimary: 12,
                usedSecondary: 4,
                credits: RawCredits(hasCredits: false, unlimited: false, balance: nil)
            )]
        )])

        let snapshot = try snapshot(from: result)
        XCTAssertEqual(snapshot.primary?.label, "5h")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 88)
        XCTAssertEqual(snapshot.secondary?.label, "7d")
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 96)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.creditsDescription, "none")
    }

    func testCanonicalCodexLimitWinsOverNewerNamedLimit() throws {
        let canonical = candidate(
            limitID: "codex",
            usedPrimary: 58,
            reportedAt: date("2026-07-20T09:43:49Z")
        )
        let named = candidate(
            limitID: "codex_spark",
            usedPrimary: 0,
            reportedAt: date("2026-07-20T09:44:07Z")
        )

        let snapshot = try snapshot(from: RateLimitReducer().reduce(summaries: [
            log(path: "/canonical.jsonl", candidates: [canonical]),
            log(path: "/named.jsonl", candidates: [named])
        ]))

        XCTAssertEqual(snapshot.primary?.remainingPercent, 42)
        XCTAssertEqual(snapshot.sourcePath, "/canonical.jsonl")
    }

    func testNewestNamedLimitIsFallbackWhenCanonicalIsAbsent() throws {
        let older = candidate(
            limitID: "codex_alpha",
            usedPrimary: 20,
            reportedAt: date("2026-07-20T09:43:49Z")
        )
        let newer = candidate(
            limitID: "codex_beta",
            usedPrimary: 30,
            reportedAt: date("2026-07-20T09:44:07Z")
        )

        let snapshot = try snapshot(from: RateLimitReducer().reduce(summaries: [
            log(path: "/older.jsonl", candidates: [older]),
            log(path: "/newer.jsonl", candidates: [newer])
        ]))
        XCTAssertEqual(snapshot.primary?.remainingPercent, 70)
        XCTAssertEqual(snapshot.sourcePath, "/newer.jsonl")
    }

    func testReportedTimestampWinsAcrossFilesThenFileDateIsFallback() throws {
        let olderReported = candidate(
            usedPrimary: 90,
            reportedAt: date("2026-07-03T04:38:11Z"),
            fileModifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let newerReported = candidate(
            usedPrimary: 20,
            reportedAt: date("2026-07-04T04:38:11Z"),
            fileModifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var output = try snapshot(from: RateLimitReducer().reduce(summaries: [
            log(path: "/newer-file.jsonl", candidates: [olderReported]),
            log(path: "/newer-event.jsonl", candidates: [newerReported])
        ]))
        XCTAssertEqual(output.primary?.remainingPercent, 80)
        XCTAssertEqual(output.sourcePath, "/newer-event.jsonl")

        let olderFile = candidate(usedPrimary: 70, reportedAt: nil, fileModifiedAt: Date(timeIntervalSince1970: 10))
        let newerFile = candidate(usedPrimary: 30, reportedAt: nil, fileModifiedAt: Date(timeIntervalSince1970: 20))
        output = try snapshot(from: RateLimitReducer().reduce(summaries: [
            log(path: "/older.jsonl", candidates: [olderFile]),
            log(path: "/newer.jsonl", candidates: [newerFile])
        ]))
        XCTAssertEqual(output.primary?.remainingPercent, 70)
        XCTAssertEqual(output.sourcePath, "/newer.jsonl")
    }

    func testMalformedValuesRemainUsableAndCreditsFallbacksArePreserved() throws {
        let malformed = RateLimitCandidate(
            limitID: nil,
            primary: RawRateLimitWindow(usedPercent: 25, windowMinutes: nil, resetsAt: nil),
            secondary: RawRateLimitWindow(usedPercent: 40, windowMinutes: 10_080, resetsAt: 1_783_630_800),
            credits: RawCredits(hasCredits: true, unlimited: false, balance: nil),
            planType: "plus",
            reportedAt: date("2026-07-03T04:38:11Z"),
            fileModifiedAt: .distantPast,
            sequence: 0,
            sourcePath: "/malformed.jsonl"
        )

        let snapshot = try snapshot(from: RateLimitReducer().reduce(summaries: [
            log(path: "/malformed.jsonl", candidates: [malformed])
        ]))
        XCTAssertEqual(snapshot.primary?.label, "--")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 75)
        XCTAssertNil(snapshot.primary?.resetsAt)
        XCTAssertEqual(snapshot.secondary?.label, "7d")
        XCTAssertEqual(snapshot.creditsDescription, "available")

        XCTAssertEqual(creditsDescription(RawCredits(hasCredits: true, unlimited: true, balance: 12)), "unlimited")
        XCTAssertEqual(creditsDescription(RawCredits(hasCredits: true, unlimited: false, balance: 12)), "12")
        XCTAssertEqual(creditsDescription(RawCredits(hasCredits: false, unlimited: false, balance: nil)), "none")
    }

    func testMissingRateLimitEventReturnsPlaceholderFailure() {
        XCTAssertEqual(
            RateLimitReducer().reduce(summaries: [log(path: "/empty.jsonl", candidates: [])]),
            .failure(UsageReadError(
                menuValue: "--",
                message: "No rate limit event found yet. Open or use Codex once to generate usage data.",
                detail: nil
            ))
        )
    }

    func testFormattingHelpers() throws {
        XCTAssertNil(UsageFormatting.remainingFromUsed(nil))
        XCTAssertNil(UsageFormatting.remainingFromUsed(.nan))
        XCTAssertNil(UsageFormatting.remainingFromUsed(.infinity))
        XCTAssertEqual(UsageFormatting.remainingFromUsed(-10), 100)
        XCTAssertEqual(UsageFormatting.remainingFromUsed(12.4), 88)
        XCTAssertEqual(UsageFormatting.remainingFromUsed(120), 0)
        XCTAssertEqual(UsageFormatting.menuLabel(nil), "--")
        XCTAssertEqual(UsageFormatting.menuLabel(-10), "0")
        XCTAssertEqual(UsageFormatting.menuLabel(42), "42")
        XCTAssertEqual(UsageFormatting.menuLabel(120), "100")
        XCTAssertEqual(UsageFormatting.percentLabel(nil), "--")
        XCTAssertEqual(UsageFormatting.percentLabel(42), "42%")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: nil), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: .nan), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: .infinity), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: Double(Int.max)), "--")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 45), "45m")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 60), "1h")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 300), "5h")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 1_440), "1d")
        XCTAssertEqual(UsageFormatting.windowLabel(minutes: 10_080), "7d")

        let calendar = utcCalendar()
        XCTAssertEqual(
            UsageFormatting.dateLabel(
                date("2026-07-05T13:38:30Z"),
                calendar: calendar,
                now: date("2026-07-05T23:59:00Z")
            ),
            "13:38:30"
        )
        XCTAssertEqual(
            UsageFormatting.dateLabel(
                date("2026-07-04T13:38:30Z"),
                calendar: calendar,
                now: date("2026-07-05T00:00:00Z")
            ),
            "Jul 4 13:38"
        )
    }

    private func candidate(
        limitID: String? = nil,
        usedPrimary: Double,
        usedSecondary: Double = 10,
        credits: RawCredits? = nil,
        reportedAt: Date? = Date(timeIntervalSince1970: 100),
        fileModifiedAt: Date = Date(timeIntervalSince1970: 90),
        sequence: Int = 0
    ) -> RateLimitCandidate {
        RateLimitCandidate(
            limitID: limitID,
            primary: RawRateLimitWindow(usedPercent: usedPrimary, windowMinutes: 300, resetsAt: 1_783_070_400),
            secondary: RawRateLimitWindow(usedPercent: usedSecondary, windowMinutes: 10_080, resetsAt: 1_783_630_800),
            credits: credits,
            planType: "plus",
            reportedAt: reportedAt,
            fileModifiedAt: fileModifiedAt,
            sequence: sequence,
            sourcePath: ""
        )
    }

    private func log(path: String, candidates: [RateLimitCandidate]) -> SessionLogSummary {
        let updatedCandidates = candidates.map { candidate in
            RateLimitCandidate(
                limitID: candidate.limitID,
                primary: candidate.primary,
                secondary: candidate.secondary,
                credits: candidate.credits,
                planType: candidate.planType,
                reportedAt: candidate.reportedAt,
                fileModifiedAt: candidate.fileModifiedAt,
                sequence: candidate.sequence,
                sourcePath: path
            )
        }
        let latest = updatedCandidates.reduce(nil as RateLimitCandidate?) { current, candidate in
            RateLimitCandidateOrdering.isNewer(candidate, than: current) ? candidate : current
        }
        return SessionLogSummary(
            path: path,
            modifiedAt: candidates.first?.fileModifiedAt ?? .distantPast,
            session: SessionIdentity(id: path, name: path, displayName: path, workingDirectory: nil, sourceKind: "Other"),
            metadataTimestamp: nil,
            dailyCounts: [:],
            latestTokenCounts: .zero,
            latestRateLimit: latest,
            lifecycle: .inactive,
            warnings: [],
            suppressedWarningCount: 0,
            isTopLevelInteractiveTUI: false
        )
    }

    private func snapshot(from result: UsageReadResult) throws -> UsageSnapshot {
        guard case let .snapshot(snapshot) = result else {
            XCTFail("Expected usable usage snapshot, got \(result)")
            throw SnapshotError.unexpectedResult
        }
        return snapshot
    }

    private func creditsDescription(_ credits: RawCredits) -> String? {
        let candidate = RateLimitCandidate(
            limitID: nil,
            primary: RawRateLimitWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            credits: credits,
            planType: nil,
            reportedAt: nil,
            fileModifiedAt: .distantPast,
            sequence: 0,
            sourcePath: "/credits.jsonl"
        )
        return try? snapshot(from: RateLimitReducer().reduce(summaries: [log(path: "/credits.jsonl", candidates: [candidate])])).creditsDescription
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }
}

private enum SnapshotError: Error {
    case unexpectedResult
}

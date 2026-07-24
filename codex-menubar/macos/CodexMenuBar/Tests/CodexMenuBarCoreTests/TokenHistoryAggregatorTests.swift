import Foundation
import XCTest
@testable import CodexMenuBarCore

final class TokenHistoryAggregatorTests: XCTestCase {
    func testDailySummaryCountsRemainCategoryIndependent() throws {
        let day = try date("2026-07-21T00:00:00Z")
        let counts = TokenCounts(total: 180, input: 125, cachedInput: 40, output: 55, reasoning: 9)

        let history = TokenHistoryAggregator().makeHistory(
            summaries: [summary(id: "session-1", name: "Parser work", dailyCounts: [day: counts])],
            calendar: utcCalendar(),
            now: try date("2026-07-21T12:00:00Z")
        )

        let usage = try XCTUnwrap(history.days.first { $0.date == day })
        XCTAssertEqual(usage.counts, counts)
        XCTAssertEqual(usage.sessions.map(\.counts.total), [180])
    }

    func testHistoryContainsExactlySixtyDaysAndMondayAlignedPadding() throws {
        let calendar = utcCalendar()
        let history = TokenHistoryAggregator().makeHistory(
            summaries: [],
            calendar: calendar,
            now: try date("2026-07-21T12:00:00Z")
        )

        XCTAssertEqual(history.days.count, 60)
        XCTAssertEqual(history.days.first?.date, try date("2026-05-23T00:00:00Z"))
        XCTAssertEqual(history.days.last?.date, try date("2026-07-21T00:00:00Z"))
        XCTAssertEqual(history.heatmapDays.count, 70)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(history.heatmapDays.first).date), 2)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(history.heatmapDays.last).date), 1)
        XCTAssertEqual(history.heatmapDays.compactMap(\.usage).count, 60)
        XCTAssertNil(history.heatmapDays.first?.usage)
        XCTAssertNil(history.heatmapDays.last?.usage)
    }

    func testDaySixtyOneAndFutureBucketsAreExcluded() throws {
        let summary = summary(
            id: "edge",
            name: "Edge",
            dailyCounts: [
                try date("2026-05-22T00:00:00Z"): counts(10),
                try date("2026-05-23T00:00:00Z"): counts(20),
                try date("2026-07-22T00:00:00Z"): counts(30)
            ]
        )
        let history = TokenHistoryAggregator().makeHistory(
            summaries: [summary],
            calendar: utcCalendar(),
            now: try date("2026-07-21T12:00:00Z")
        )

        XCTAssertEqual(history.days.first?.counts.total, 20)
        XCTAssertEqual(history.days.reduce(0) { $0 + $1.counts.total }, 20)
    }

    func testLocalCalendarUsesLocalDayBucketsAcrossDST() throws {
        var calendar = utcCalendar()
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let march7 = calendar.startOfDay(for: try date("2026-03-08T07:30:00Z"))
        let march8 = calendar.startOfDay(for: try date("2026-03-08T08:30:00Z"))
        let history = TokenHistoryAggregator().makeHistory(
            summaries: [summary(id: "dst", name: "DST work", dailyCounts: [march7: counts(10), march8: counts(50)])],
            calendar: calendar,
            now: try date("2026-03-09T18:00:00Z")
        )

        XCTAssertEqual(history.days.first { $0.date == march7 }?.counts.total, 10)
        XCTAssertEqual(history.days.first { $0.date == march8 }?.counts.total, 50)
        XCTAssertEqual(history.days.count, 60)
    }

    func testYearBoundaryPreservesDailySummaries() throws {
        let december31 = try date("2025-12-31T00:00:00Z")
        let january1 = try date("2026-01-01T00:00:00Z")
        let history = TokenHistoryAggregator().makeHistory(
            summaries: [summary(id: "year", name: "Year work", dailyCounts: [december31: counts(100), january1: counts(40)])],
            calendar: utcCalendar(),
            now: try date("2026-01-02T12:00:00Z")
        )

        XCTAssertEqual(history.days.first { $0.date == december31 }?.counts.total, 100)
        XCTAssertEqual(history.days.first { $0.date == january1 }?.counts.total, 40)
    }

    func testAllSourceKindsContributeAndSessionsSortByTotalThenName() throws {
        let day = try date("2026-07-21T00:00:00Z")
        let summaries = [
            summary(id: "z", name: "Zulu", sourceKind: "cli", dailyCounts: [day: counts(50)]),
            summary(id: "a", name: "Alpha", sourceKind: "vscode", dailyCounts: [day: counts(50)]),
            summary(id: "b", name: "Beta", sourceKind: "exec", dailyCounts: [day: counts(80)])
        ]
        let history = TokenHistoryAggregator().makeHistory(
            summaries: summaries,
            calendar: utcCalendar(),
            now: try date("2026-07-21T12:00:00Z")
        )
        let today = try XCTUnwrap(history.days.first { $0.date == day })

        XCTAssertEqual(today.counts.total, 180)
        XCTAssertEqual(today.sessions.map(\.session.name), ["Beta", "Alpha", "Zulu"])
        XCTAssertEqual(Set(today.sessions.map(\.session.sourceKind)), Set(["cli", "vscode", "exec"]))
    }

    func testHeatLevelsUseNonzeroDailyQuartiles() throws {
        let summaries = try [10, 20, 30, 40].enumerated().map { index, total in
            summary(
                id: "session-\(index)",
                name: "Session \(index)",
                dailyCounts: [try date("2026-07-\(17 + index)T00:00:00Z"): counts(Int64(total))]
            )
        }
        let history = TokenHistoryAggregator().makeHistory(
            summaries: summaries,
            calendar: utcCalendar(),
            now: try date("2026-07-21T12:00:00Z")
        )
        let levels = history.days
            .filter { $0.counts.total > 0 }
            .sorted { $0.counts.total < $1.counts.total }
            .map(\.heatLevel)

        XCTAssertEqual(levels, [1, 2, 3, 4])
    }

    private func summary(
        id: String,
        name: String,
        sourceKind: String = "cli",
        dailyCounts: [Date: TokenCounts]
    ) -> SessionLogSummary {
        SessionLogSummary(
            path: "/tmp/\(id).jsonl",
            modifiedAt: dailyCounts.keys.max() ?? .distantPast,
            session: SessionIdentity(
                id: id,
                name: name,
                displayName: name,
                workingDirectory: "/tmp/\(id)",
                sourceKind: sourceKind
            ),
            metadataTimestamp: dailyCounts.keys.min(),
            dailyCounts: dailyCounts,
            latestTokenCounts: dailyCounts.values.reduce(.zero) { $0 + $1 },
            latestRateLimit: nil,
            lifecycle: .inactive,
            warnings: [],
            suppressedWarningCount: 0,
            isTopLevelLiveSession: false
        )
    }

    private func counts(_ total: Int64) -> TokenCounts {
        TokenCounts(total: total, input: 0, cachedInput: 0, output: 0, reasoning: 0)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }
}

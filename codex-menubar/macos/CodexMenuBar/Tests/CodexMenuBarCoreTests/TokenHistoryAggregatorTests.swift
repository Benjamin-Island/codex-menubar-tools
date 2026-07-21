import XCTest
@testable import CodexMenuBarCore

final class TokenHistoryAggregatorTests: XCTestCase {
    func testCumulativeEventsBecomeNonDuplicatedDailyIncrements() throws {
        let calendar = utcCalendar()
        let day = try date("2026-07-21T00:00:00Z")
        let log = makeLog(
            id: "session-1",
            name: "Parser work",
            events: [
                event("2026-07-21T01:00:00Z", total: 100, input: 70, cached: 20, output: 30, reasoning: 4, sequence: 1),
                event("2026-07-21T02:00:00Z", total: 160, input: 110, cached: 35, output: 50, reasoning: 7, sequence: 2),
                event("2026-07-21T03:00:00Z", total: 160, input: 110, cached: 35, output: 50, reasoning: 7, sequence: 3),
                event("2026-07-21T04:00:00Z", total: 20, input: 15, cached: 5, output: 5, reasoning: 2, sequence: 4)
            ]
        )

        let history = TokenHistoryAggregator().makeHistory(
            logs: [log],
            calendar: calendar,
            now: try date("2026-07-21T12:00:00Z")
        )

        let usage = try XCTUnwrap(history.days.first { $0.date == day })
        XCTAssertEqual(
            usage.counts,
            TokenCounts(total: 180, input: 125, cachedInput: 40, output: 55, reasoning: 9)
        )
        XCTAssertEqual(usage.sessions.map(\.counts.total), [180])
    }

    func testHistoryContainsExactlyThirtyMondayFirstWeeksAndDisablesFutureDays() throws {
        let calendar = utcCalendar()
        let history = TokenHistoryAggregator().makeHistory(
            logs: [
                makeLog(
                    id: "future",
                    name: "Future log",
                    events: [event("2026-07-24T10:00:00Z", total: 50, sequence: 1)]
                )
            ],
            calendar: calendar,
            now: try date("2026-07-21T12:00:00Z")
        )

        XCTAssertEqual(history.days.count, 210)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(history.days.first).date), 2)
        XCTAssertEqual(history.days.filter(\.isFuture).count, 5)
        let futureDate = try date("2026-07-24T00:00:00Z")
        let future = try XCTUnwrap(history.days.first { $0.date == futureDate })
        XCTAssertEqual(future.counts, .zero)
        XCTAssertEqual(future.heatLevel, 0)
    }

    func testLocalCalendarAssignsEventsAcrossMidnightAndDST() throws {
        var calendar = utcCalendar()
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let log = makeLog(
            id: "session-1",
            name: "DST work",
            events: [
                event("2026-03-08T07:30:00Z", total: 10, sequence: 1),
                event("2026-03-08T08:30:00Z", total: 30, sequence: 2),
                event("2026-03-09T06:30:00Z", total: 60, sequence: 3)
            ]
        )

        let history = TokenHistoryAggregator().makeHistory(
            logs: [log],
            calendar: calendar,
            now: try date("2026-03-09T18:00:00Z")
        )

        let march7 = calendar.startOfDay(for: try date("2026-03-08T07:30:00Z"))
        let march8 = calendar.startOfDay(for: try date("2026-03-08T08:30:00Z"))
        XCTAssertEqual(history.days.first { $0.date == march7 }?.counts.total, 10)
        XCTAssertEqual(history.days.first { $0.date == march8 }?.counts.total, 50)
        XCTAssertEqual(history.days.count, 210)
    }

    func testYearBoundaryAndSessionSpanningDaysPreserveDailyIncrements() throws {
        let calendar = utcCalendar()
        let log = makeLog(
            id: "year-session",
            name: "Year work",
            events: [
                event("2025-12-31T23:00:00Z", total: 100, sequence: 1),
                event("2026-01-01T01:00:00Z", total: 140, sequence: 2)
            ]
        )

        let history = TokenHistoryAggregator().makeHistory(
            logs: [log],
            calendar: calendar,
            now: try date("2026-01-02T12:00:00Z")
        )

        let december31 = try date("2025-12-31T00:00:00Z")
        let january1 = try date("2026-01-01T00:00:00Z")
        XCTAssertEqual(history.days.first { $0.date == december31 }?.counts.total, 100)
        XCTAssertEqual(history.days.first { $0.date == january1 }?.counts.total, 40)
    }

    func testAllSourceKindsContributeAndSessionsSortByTotalThenName() throws {
        let calendar = utcCalendar()
        let logs = [
            makeLog(id: "z", name: "Zulu", sourceKind: "cli", events: [event("2026-07-21T01:00:00Z", total: 50, sequence: 1)]),
            makeLog(id: "a", name: "Alpha", sourceKind: "vscode", events: [event("2026-07-21T02:00:00Z", total: 50, sequence: 1)]),
            makeLog(id: "b", name: "Beta", sourceKind: "exec", events: [event("2026-07-21T03:00:00Z", total: 80, sequence: 1)])
        ]

        let history = TokenHistoryAggregator().makeHistory(
            logs: logs,
            calendar: calendar,
            now: try date("2026-07-21T12:00:00Z")
        )
        let todayDate = try date("2026-07-21T00:00:00Z")
        let today = try XCTUnwrap(history.days.first { $0.date == todayDate })

        XCTAssertEqual(today.counts.total, 180)
        XCTAssertEqual(today.sessions.map(\.session.name), ["Beta", "Alpha", "Zulu"])
        XCTAssertEqual(Set(today.sessions.map(\.session.sourceKind)), Set(["cli", "vscode", "exec"]))
    }

    func testHeatLevelsUseNonzeroDailyQuartiles() throws {
        let calendar = utcCalendar()
        let logs = [10, 20, 30, 40].enumerated().map { index, total in
            makeLog(
                id: "session-\(index)",
                name: "Session \(index)",
                events: [event("2026-07-\(17 + index)T12:00:00Z", total: Int64(total), sequence: 1)]
            )
        }

        let history = TokenHistoryAggregator().makeHistory(
            logs: logs,
            calendar: calendar,
            now: try date("2026-07-21T12:00:00Z")
        )
        let levels = history.days
            .filter { $0.counts.total > 0 }
            .sorted { $0.counts.total < $1.counts.total }
            .map(\.heatLevel)

        XCTAssertEqual(levels, [1, 2, 3, 4])
    }

    private func makeLog(
        id: String,
        name: String,
        sourceKind: String = "cli",
        events: [TokenEvent]
    ) -> IndexedSessionLog {
        IndexedSessionLog(
            path: "/tmp/\(id).jsonl",
            modifiedAt: events.last?.timestamp ?? .distantPast,
            session: SessionIdentity(
                id: id,
                name: name,
                displayName: name,
                workingDirectory: "/tmp/\(id)",
                sourceKind: sourceKind
            ),
            metadataTimestamp: events.first?.timestamp,
            tokenEvents: events,
            rateLimits: [],
            lifecycle: .inactive,
            warnings: []
        )
    }

    private func event(
        _ timestamp: String,
        total: Int64,
        input: Int64 = 0,
        cached: Int64 = 0,
        output: Int64 = 0,
        reasoning: Int64 = 0,
        sequence: Int
    ) -> TokenEvent {
        TokenEvent(
            timestamp: try! date(timestamp),
            cumulative: TokenCounts(
                total: total,
                input: input,
                cachedInput: cached,
                output: output,
                reasoning: reasoning
            ),
            sequence: sequence
        )
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

import Foundation
import XCTest
@testable import CodexMenuBarCore

final class SummaryConsumerTests: XCTestCase {
    func testHistoryMergesPerFileDailySummariesBySession() throws {
        let day = try date("2026-07-21T00:00:00Z")
        let summaries = [
            summary(path: "/a.jsonl", id: "same", day: day, total: 40),
            summary(path: "/b.jsonl", id: "same", day: day, total: 60)
        ]

        let history = TokenHistoryAggregator().makeHistory(
            summaries: summaries,
            calendar: utcCalendar(),
            now: day
        )

        XCTAssertEqual(history.days.last?.counts.total, 100)
        XCTAssertEqual(history.days.last?.sessions.count, 1)
    }

    func testRateReducerUsesOneCandidatePerSummary() throws {
        let older = candidate(path: "/older.jsonl", used: 80, reportedAt: try date("2026-07-21T01:00:00Z"))
        let newer = candidate(path: "/newer.jsonl", used: 20, reportedAt: try date("2026-07-21T02:00:00Z"))

        let result = RateLimitReducer().reduce(summaries: [
            summary(path: older.sourcePath, rate: older),
            summary(path: newer.sourcePath, rate: newer)
        ])

        guard case let .snapshot(snapshot) = result else { return XCTFail("Expected usage snapshot") }
        XCTAssertEqual(snapshot.sourcePath, newer.sourcePath)
        XCTAssertEqual(snapshot.primary?.remainingPercent, 80)
    }

    func testLiveSessionUsesLatestSummaryTokenCounts() throws {
        let now = try date("2026-07-21T02:00:00Z")
        let inventory = SessionInventory(
            processProvider: EmptyProcessProvider(),
            classifier: InteractiveTUIClassifier(),
            currentUID: 501
        )
        let process = ProcessSnapshot(
            pid: 42,
            parentPID: 1,
            userID: 501,
            startedAt: try date("2026-07-21T00:00:00Z"),
            executablePath: "/usr/local/bin/codex",
            arguments: ["codex"],
            workingDirectory: "/tmp/project",
            hasControllingTerminal: true,
            openFilePaths: ["/sessions/a.jsonl"]
        )

        let result = inventory.read(
            summaries: [summary(path: "/sessions/a.jsonl", latestTotal: 321, topLevel: true)],
            candidates: [process],
            now: now
        )

        guard case let .snapshots(items) = result else { return XCTFail("Expected sessions") }
        XCTAssertEqual(items.first?.tokenCounts.total, 321)
    }

    private func summary(
        path: String,
        id: String = "session",
        day: Date? = nil,
        total: Int64 = 0,
        latestTotal: Int64 = 0,
        rate: RateLimitCandidate? = nil,
        topLevel: Bool = false
    ) -> SessionLogSummary {
        SessionLogSummary(
            path: path,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            session: SessionIdentity(
                id: id,
                name: "Session",
                displayName: "Session",
                workingDirectory: "/tmp/project",
                sourceKind: "cli"
            ),
            metadataTimestamp: Date(timeIntervalSince1970: 1_799_999_900),
            dailyCounts: day.map {
                [$0: TokenCounts(total: total, input: total, cachedInput: 0, output: 0, reasoning: 0)]
            } ?? [:],
            latestTokenCounts: TokenCounts(
                total: latestTotal,
                input: latestTotal,
                cachedInput: 0,
                output: 0,
                reasoning: 0
            ),
            latestRateLimit: rate,
            lifecycle: .active,
            warnings: [],
            suppressedWarningCount: 0,
            isTopLevelLiveSession: topLevel
        )
    }

    private func candidate(path: String, used: Double, reportedAt: Date) -> RateLimitCandidate {
        RateLimitCandidate(
            limitID: "codex",
            primary: RawRateLimitWindow(usedPercent: used, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            credits: nil,
            planType: "plus",
            reportedAt: reportedAt,
            fileModifiedAt: reportedAt,
            sequence: 1,
            sourcePath: path
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

private struct EmptyProcessProvider: ProcessProviding {
    func processSnapshots() throws -> [ProcessSnapshot] { [] }
}

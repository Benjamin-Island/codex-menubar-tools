import Foundation
import XCTest
@testable import CodexMenuBarCore

final class SessionLogAccumulatorTests: XCTestCase {
    private let modifiedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testAccumulatorKeepsDailyTotalsAndCurrentStateWithoutRawEvents() throws {
        var accumulator = makeAccumulator()
        let cutoff = try date("2026-05-23T00:00:00Z")
        let today = try date("2026-07-21T00:00:00Z")

        consume(token(total: 100, input: 70, at: "2026-05-22T23:00:00Z"), line: 1, into: &accumulator, cutoff: cutoff, today: today)
        consume(token(total: 160, input: 110, at: "2026-05-23T01:00:00Z"), line: 2, into: &accumulator, cutoff: cutoff, today: today)
        consume(token(total: 20, input: 15, at: "2026-05-23T02:00:00Z"), line: 3, into: &accumulator, cutoff: cutoff, today: today)

        let summary = accumulator.summary(modifiedAt: modifiedAt, threadName: nil)
        XCTAssertEqual(summary.dailyCounts[cutoff]?.total, 80)
        XCTAssertEqual(summary.dailyCounts[cutoff]?.input, 55)
        XCTAssertEqual(summary.latestTokenCounts.total, 20)
        XCTAssertLessThanOrEqual(summary.dailyCounts.count, 60)
    }

    func testAccumulatorRetainsOnlyNewestRateLimit() throws {
        var accumulator = makeAccumulator()
        let cutoff = try date("2026-05-23T00:00:00Z")
        let today = try date("2026-07-21T00:00:00Z")

        consume(limit(used: 50, at: "2026-07-21T01:00:00Z"), line: 1, into: &accumulator, cutoff: cutoff, today: today)
        consume(limit(used: 20, at: "2026-07-21T02:00:00Z"), line: 2, into: &accumulator, cutoff: cutoff, today: today)

        XCTAssertEqual(accumulator.summary(modifiedAt: modifiedAt, threadName: nil).latestRateLimit?.primary?.usedPercent, 20)
    }

    func testFallbackNameAndWarningsAreBounded() throws {
        var accumulator = makeAccumulator(maximumWarnings: 2, maximumNameCharacters: 5)
        let cutoff = try date("2026-05-23T00:00:00Z")
        let today = try date("2026-07-21T00:00:00Z")

        consume(userMessage(String(repeating: "x", count: 100)), line: 1, into: &accumulator, cutoff: cutoff, today: today)
        accumulator.consume(warning: ParseWarning(path: "/a.jsonl", line: 2, message: "one"))
        accumulator.consume(warning: ParseWarning(path: "/a.jsonl", line: 3, message: "two"))
        accumulator.consume(warning: ParseWarning(path: "/a.jsonl", line: 4, message: "three"))

        let summary = accumulator.summary(modifiedAt: modifiedAt, threadName: nil)
        XCTAssertEqual(summary.session.name, "xxxxx")
        XCTAssertEqual(summary.warnings.count, 2)
        XCTAssertEqual(summary.suppressedWarningCount, 1)
    }

    func testMetadataAndLifecyclePreserveCurrentSessionState() throws {
        var accumulator = makeAccumulator()
        let cutoff = try date("2026-05-23T00:00:00Z")
        let today = try date("2026-07-21T00:00:00Z")

        consume(metadata(), line: 1, into: &accumulator, cutoff: cutoff, today: today)
        consume(#"{"type":"event_msg","payload":{"type":"task_started"}}"#, line: 2, into: &accumulator, cutoff: cutoff, today: today)

        let summary = accumulator.summary(modifiedAt: modifiedAt, threadName: " Named   thread ")
        XCTAssertEqual(accumulator.sessionID, "session-1")
        XCTAssertEqual(summary.session.name, "Named thread")
        XCTAssertEqual(summary.session.workingDirectory, "/tmp/project")
        XCTAssertEqual(summary.session.sourceKind, "cli")
        XCTAssertEqual(summary.lifecycle, .active)
        XCTAssertTrue(summary.isTopLevelInteractiveTUI)
    }

    private func makeAccumulator(
        maximumWarnings: Int = 20,
        maximumNameCharacters: Int = 512
    ) -> SessionLogAccumulator {
        SessionLogAccumulator(
            path: "/a.jsonl",
            maximumWarnings: maximumWarnings,
            maximumNameCharacters: maximumNameCharacters
        )
    }

    private func consume(
        _ json: String,
        line: Int,
        into accumulator: inout SessionLogAccumulator,
        cutoff: Date,
        today: Date
    ) {
        accumulator.consume(
            record: JSONLRecord(data: Data(json.utf8), lineNumber: line),
            modifiedAt: modifiedAt,
            cutoff: cutoff,
            today: today,
            calendar: utcCalendar()
        )
    }

    private func token(total: Int, input: Int, at timestamp: String) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total),"input_tokens":\(input)}}}}
        """
    }

    private func limit(used: Int, at timestamp: String) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":\(used),"window_minutes":300}}}}
        """
    }

    private func userMessage(_ message: String) -> String {
        """
        {"type":"event_msg","payload":{"type":"user_message","message":"\(message)"}}
        """
    }

    private func metadata() -> String {
        #"{"timestamp":"2026-07-21T01:00:00Z","type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/project","source":"cli","originator":"codex-tui","thread_source":"user"}}"#
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

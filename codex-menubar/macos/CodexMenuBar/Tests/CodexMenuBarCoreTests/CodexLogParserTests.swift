import Foundation
import XCTest
@testable import CodexMenuBarCore

final class CodexLogParserTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncrementalParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testIndexesIdentityTokensLifecycleNamesAndWarningsInOnePass() throws {
        let records = [
            metadata(id: "session-1", cwd: "/tmp/project", source: "cli", originator: "codex-tui", threadSource: "user"),
            #"{"timestamp":"2026-07-21T01:01:00Z","type":"event_msg","payload":{"type":"user_message","message":"fallback message"}}"#,
            tokenRecord(timestamp: "2026-07-21T01:02:00Z", total: 100, input: 80),
            tokenRecord(timestamp: "2026-07-21T01:03:00Z", total: 160, input: 125),
            #"{"timestamp":"2026-07-21T01:04:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            "{malformed"
        ]

        let summary = try parse(records: records, indexedName: "Named thread")

        XCTAssertEqual(summary.session.id, "session-1")
        XCTAssertEqual(summary.session.name, "Named thread")
        XCTAssertEqual(summary.session.workingDirectory, "/tmp/project")
        XCTAssertEqual(summary.session.sourceKind, "cli")
        XCTAssertEqual(summary.latestTokenCounts.total, 160)
        XCTAssertEqual(summary.dailyCounts.values.first?.total, 160)
        XCTAssertEqual(summary.lifecycle, .active)
        XCTAssertEqual(summary.warnings.count, 1)
        XCTAssertTrue(summary.isTopLevelInteractiveTUI)
    }

    func testFallsBackToMessageThenDirectoryThenUntitledSession() throws {
        var summary = try parse(records: [
            metadata(id: "message", cwd: "/tmp/project", source: "cli"),
            #"{"type":"event_msg","payload":{"type":"user_message","message":"  fix\n  the   parser  "}}"#
        ])
        XCTAssertEqual(summary.session.name, "fix the parser")

        summary = try parse(records: [metadata(id: "directory", cwd: "/tmp/customer-api", source: "cli")])
        XCTAssertEqual(summary.session.name, "customer-api")

        summary = try parse(records: [#"{"type":"event_msg","payload":{"type":"agent_message"}}"#])
        XCTAssertEqual(summary.session.name, "Untitled session")
        XCTAssertEqual(summary.session.id, summary.path)
    }

    func testMissingTimestampExcludesTokenTotalsButRetainsRateLimit() throws {
        let summary = try parse(records: [
            metadata(id: "limits", cwd: "/tmp/project", source: "cli"),
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":25,"window_minutes":300}}}}"#
        ])

        XCTAssertEqual(summary.latestTokenCounts, .zero)
        XCTAssertTrue(summary.dailyCounts.isEmpty)
        XCTAssertNil(summary.latestRateLimit?.reportedAt)
        XCTAssertEqual(summary.latestRateLimit?.primary?.usedPercent, 25)
    }

    func testTaskCompleteAfterStartProducesInactiveLifecycle() throws {
        let summary = try parse(records: [
            metadata(id: "complete", cwd: "/tmp/project", source: "cli"),
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
        ])
        XCTAssertEqual(summary.lifecycle, .inactive)
    }

    func testSourceClassificationCoversCLIIDEExecAppAndOther() throws {
        let cases = [
            ("cli", "codex-tui", "user", "cli"),
            ("unknown", "vscode", "user", "IDE"),
            ("vscode", "Codex Desktop", "user", "App"),
            ("unknown", "exec", "user", "exec"),
            ("unknown", "chatgpt-app", "user", "App"),
            ("mystery", "unknown", "unknown", "Other")
        ]
        for (source, originator, threadSource, expected) in cases {
            let summary = try parse(records: [
                metadata(id: UUID().uuidString, cwd: "/tmp/project", source: source, originator: originator, threadSource: threadSource)
            ])
            XCTAssertEqual(summary.session.sourceKind, expected)
        }
    }

    func testTokenRateAndCreditsDecodeTolerantlyAtIntegerBoundary() throws {
        let summary = try parse(records: [
            metadata(id: "tolerant", cwd: "/tmp/project", source: "mystery"),
            #"{"timestamp":"2026-07-21T01:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":"120","input_tokens":-1,"cached_input_tokens":"40","output_tokens":9223372036854775808,"reasoning_output_tokens":7}},"rate_limits":{"primary":{"used_percent":25,"window_minutes":{"unexpected":true},"resets_at":["soon"]},"secondary":{"used_percent":"40","window_minutes":"10080","resets_at":"1783630800"},"credits":{"has_credits":"true","unlimited":"false","balance":9223372036854775808},"plan_type":"plus"}}}"#
        ])

        XCTAssertEqual(summary.latestTokenCounts, TokenCounts(total: 120, input: 0, cachedInput: 40, output: 0, reasoning: 7))
        XCTAssertNil(summary.latestRateLimit?.primary?.windowMinutes)
        XCTAssertEqual(summary.latestRateLimit?.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(summary.latestRateLimit?.credits?.hasCredits, true)
        XCTAssertNil(summary.latestRateLimit?.credits?.balance)
    }

    func testIncompleteFinalLineWaitsWithoutDiscardingEarlierRecords() throws {
        let summary = try parse(
            records: [
                metadata(id: "incomplete", cwd: "/tmp/project", source: "cli"),
                tokenRecord(timestamp: "2026-07-21T01:02:00Z", total: 100, input: 80),
                #"{"type":"event_msg","payload":{"type":"token_count""#
            ],
            terminatesWithNewline: false
        )

        XCTAssertEqual(summary.latestTokenCounts.total, 100)
        XCTAssertTrue(summary.warnings.isEmpty)
    }

    func testDisplayDescriptionTruncatesUnicodeAtSixtyCharacters() {
        let value = String(repeating: "🙂", count: 61)
        XCTAssertEqual(SessionTextFormatting.displayDescription(value), String(repeating: "🙂", count: 60))
    }

    private func parse(
        records: [String],
        indexedName: String? = nil,
        terminatesWithNewline: Bool = true
    ) throws -> SessionLogSummary {
        let sessions = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let logURL = sessions.appendingPathComponent("rollout.jsonl")
        let text = records.joined(separator: "\n") + (terminatesWithNewline ? "\n" : "")
        try Data(text.utf8).write(to: logURL)
        let indexURL = sessions.appendingPathComponent("session_index.jsonl")
        if let indexedName {
            try Data("{\"id\":\"session-1\",\"thread_name\":\"\(indexedName)\"}\n".utf8).write(to: indexURL)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let snapshot = try IncrementalCodexLogIndex().refresh(
            sessionsDirectory: sessions,
            modifiedSince: .distantPast,
            requiredPaths: [],
            calendar: calendar,
            now: try date("2026-07-21T12:00:00Z"),
            sessionIndexURL: indexURL
        )
        return try XCTUnwrap(snapshot.summaries.first)
    }

    private func metadata(
        id: String,
        cwd: String,
        source: String,
        originator: String = "unknown",
        threadSource: String = "unknown"
    ) -> String {
        #"{"timestamp":"2026-07-21T01:00:00Z","type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)","source":"\#(source)","originator":"\#(originator)","thread_source":"\#(threadSource)"}}"#
    }

    private func tokenRecord(timestamp: String, total: Int, input: Int) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\#(total),"input_tokens":\#(input)}}}}"#
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }
}

import XCTest
@testable import CodexMenuBarCore

final class CodexLogParserTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexLogParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testParsesIdentityTokensLifecycleAndWarningsInOnePass() throws {
        let logURL = temporaryDirectory.appendingPathComponent("rollout.jsonl")
        let records = [
            #"{"timestamp":"2026-07-21T01:00:00Z","type":"session_meta","payload":{"id":"session-1","session_id":"session-1","timestamp":"2026-07-21T01:00:00Z","cwd":"/tmp/project","source":"cli","originator":"codex-tui","thread_source":"user"}}"#,
            #"{"timestamp":"2026-07-21T01:01:00Z","type":"event_msg","payload":{"type":"user_message","message":"  fallback   message  "}}"#,
            tokenRecord(timestamp: "2026-07-21T01:02:00Z", total: 100, input: 80, cached: 30, output: 20, reasoning: 4),
            tokenRecord(timestamp: "2026-07-21T01:03:00Z", total: 160, input: 125, cached: 45, output: 35, reasoning: 7),
            #"{"timestamp":"2026-07-21T01:04:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            "{malformed"
        ]
        try records.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)

        let log = try CodexLogParser().parse(
            logURL: logURL,
            sessionNames: ["session-1": "Named thread"],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(log.session.id, "session-1")
        XCTAssertEqual(log.session.name, "Named thread")
        XCTAssertEqual(log.session.workingDirectory, "/tmp/project")
        XCTAssertEqual(log.session.sourceKind, "cli")
        XCTAssertEqual(log.tokenEvents.map(\.cumulative.total), [100, 160])
        XCTAssertEqual(log.lifecycle, .active)
        XCTAssertEqual(log.warnings.count, 1)
        XCTAssertTrue(log.isTopLevelInteractiveTUI)
    }

    func testFallsBackToNormalizedFirstUserMessage() throws {
        let log = try parse(records: [
            sessionMetadata(id: "session-2", cwd: "/tmp/project", source: "cli"),
            #"{"type":"event_msg","payload":{"type":"user_message","message":"  fix\n  the   parser  "}}"#
        ])

        XCTAssertEqual(log.session.name, "fix the parser")
        XCTAssertEqual(log.session.displayName, "fix the parser")
    }

    func testFallsBackToDirectoryThenUntitledSession() throws {
        let directoryLog = try parse(records: [
            sessionMetadata(id: "session-3", cwd: "/tmp/customer-api", source: "cli")
        ])
        let untitledLog = try parse(records: [#"{"type":"event_msg","payload":{"type":"agent_message"}}"#])

        XCTAssertEqual(directoryLog.session.name, "customer-api")
        XCTAssertEqual(untitledLog.session.name, "Untitled session")
        XCTAssertEqual(untitledLog.session.id, untitledLog.path)
    }

    func testMissingTimestampExcludesTokenEventButRetainsRateLimit() throws {
        let log = try parse(records: [
            sessionMetadata(id: "session-4", cwd: "/tmp/project", source: "cli"),
            """
            {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":25,"window_minutes":300,"resets_at":1783070400}}}}
            """
        ])

        XCTAssertTrue(log.tokenEvents.isEmpty)
        XCTAssertEqual(log.rateLimits.count, 1)
        XCTAssertNil(log.rateLimits[0].reportedAt)
        XCTAssertEqual(log.rateLimits[0].primary?.usedPercent, 25)
    }

    func testTaskCompleteAfterStartProducesInactiveLifecycle() throws {
        let log = try parse(records: [
            sessionMetadata(id: "session-5", cwd: "/tmp/project", source: "cli"),
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
        ])

        XCTAssertEqual(log.lifecycle, .inactive)
    }

    func testUnknownSourceAndInvalidTokenFieldsRemainUsable() throws {
        let log = try parse(records: [
            sessionMetadata(id: "session-6", cwd: "/tmp/project", source: "mystery"),
            """
            {"timestamp":"2026-07-21T01:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":"120","input_tokens":-1,"cached_input_tokens":"40","output_tokens":9223372036854775808,"reasoning_output_tokens":7}}}}
            """
        ])

        XCTAssertEqual(log.session.sourceKind, "Other")
        XCTAssertFalse(log.isTopLevelInteractiveTUI)
        XCTAssertEqual(
            log.tokenEvents[0].cumulative,
            TokenCounts(total: 120, input: 0, cachedInput: 40, output: 0, reasoning: 7)
        )
    }

    func testReadsNormalizedSessionNamesAndSkipsMalformedIndexLines() throws {
        let indexURL = temporaryDirectory.appendingPathComponent("session_index.jsonl")
        try [
            #"{"id":"session-1","thread_name":"  Named   thread "}"#,
            "{malformed",
            #"{"id":"session-2","thread_name":""}"#
        ].joined(separator: "\n").write(to: indexURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(try CodexLogParser().readSessionNames(at: indexURL), ["session-1": "Named thread"])
    }

    private func parse(records: [String]) throws -> IndexedSessionLog {
        let logURL = temporaryDirectory.appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        try records.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
        return try CodexLogParser().parse(
            logURL: logURL,
            sessionNames: [:],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func sessionMetadata(id: String, cwd: String, source: String) -> String {
        """
        {"timestamp":"2026-07-21T01:00:00Z","type":"session_meta","payload":{"id":"\(id)","session_id":"\(id)","timestamp":"2026-07-21T01:00:00Z","cwd":"\(cwd)","source":"\(source)","originator":"unknown","thread_source":"unknown"}}
        """
    }

    private func tokenRecord(
        timestamp: String,
        total: Int,
        input: Int,
        cached: Int,
        output: Int,
        reasoning: Int
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total),"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning)}}}}
        """
    }
}

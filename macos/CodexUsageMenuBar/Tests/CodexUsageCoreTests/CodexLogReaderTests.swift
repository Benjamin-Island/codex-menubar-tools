import XCTest
@testable import CodexUsageCore

final class CodexLogReaderTests: XCTestCase {
    private var tempDirectory: URL!
    private var reader: CodexLogReader!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexUsageMenuBarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        reader = CodexLogReader()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testReadsPrimaryAndSecondaryRemaining() throws {
        let session = tempDirectory.appendingPathComponent("2026/07/05/session.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 12, usedSecondary: 4)], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.label, "5h")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 88)
        XCTAssertEqual(snapshot.secondary?.label, "7d")
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 96)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.creditsDescription, "none")
    }

    func testSkipsBadJsonAndUsesOlderValidEvent() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [tokenCountEvent(usedPrimary: 45, usedSecondary: 10), "{bad json"], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .snapshot(snapshot) = result else {
            return XCTFail("Expected snapshot, got \(result)")
        }
        XCTAssertEqual(snapshot.primary?.remainingPercent, 55)
    }

    func testMissingSessionsDirectoryReturnsFailure() {
        let missing = tempDirectory.appendingPathComponent("missing")

        let result = reader.readLatestSnapshot(sessionsDirectory: missing)

        XCTAssertEqual(result, .failure(UsageReadError(
            menuValue: "--",
            message: "No Codex session directory found",
            detail: missing.path
        )))
    }

    func testNoRateLimitEventReturnsFailure() throws {
        let session = tempDirectory.appendingPathComponent("session.jsonl")
        try write(records: [#"{"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}"#], to: session)

        let result = reader.readLatestSnapshot(sessionsDirectory: tempDirectory)

        guard case let .failure(error) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(error.menuValue, "--")
        XCTAssertTrue(error.message.contains("No rate limit event"))
    }

    private func write(records: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try records.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func tokenCountEvent(usedPrimary: Int, usedSecondary: Int) -> String {
        """
        {"timestamp":"2026-07-03T04:38:11.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\(usedPrimary),"window_minutes":300,"resets_at":1783070400},"secondary":{"used_percent":\(usedSecondary),"window_minutes":10080,"resets_at":1783630800},"credits":{"has_credits":false,"unlimited":false,"balance":null},"plan_type":"plus"}}}
        """
    }
}

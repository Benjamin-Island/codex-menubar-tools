import Foundation
import XCTest
@testable import CodexSessionCore

final class CodexSessionLogReaderTests: XCTestCase {
    private var tempDirectory: URL!
    private var logURL: URL!
    private var indexURL: URL!
    private var reader: CodexSessionLogReader!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSessionLogReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        logURL = tempDirectory.appendingPathComponent("rollout.jsonl")
        indexURL = tempDirectory.appendingPathComponent("session_index.jsonl")
        reader = CodexSessionLogReader()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testNamedSessionOverridesFirstUserMessageAndRecentTaskIsRunning() throws {
        try writeLog([
            sessionMeta(),
            userMessage("first task"),
            taskStarted()
        ])
        try writeIndex([#"{"id":"s1","thread_name":"Renamed task","updated_at":"2026-07-20T06:00:00Z"}"#])

        let snapshot = try XCTUnwrap(reader.readSession(
            at: logURL,
            sessionNames: try reader.readSessionNames(at: indexURL),
            modifiedAt: try date("2026-07-20T06:01:00Z"),
            now: try date("2026-07-20T06:02:00Z")
        ))

        XCTAssertEqual(snapshot.sessionID, "s1")
        XCTAssertEqual(snapshot.taskDescription, "Renamed task")
        XCTAssertEqual(snapshot.displayTaskDescription, "Renamed task")
        XCTAssertEqual(snapshot.activity, .running)
        XCTAssertEqual(snapshot.workingDirectory, "/tmp/work")
    }

    func testFirstUserMessageCollapsesWhitespaceWhenSessionIsUnnamed() throws {
        try writeLog([sessionMeta(), userMessage("  fix\n   login\t tests  "), taskComplete()])

        let snapshot = try XCTUnwrap(readSession())

        XCTAssertEqual(snapshot.taskDescription, "fix login tests")
        XCTAssertEqual(snapshot.activity, .stalled)
    }

    func testDirectoryNameIsFallbackWhenNoTaskTextExists() throws {
        try writeLog([sessionMeta(cwd: "/tmp/customer-api")])

        let snapshot = try XCTUnwrap(readSession())

        XCTAssertEqual(snapshot.taskDescription, "customer-api")
        XCTAssertEqual(snapshot.activity, .stalled)
    }

    func testRejectsNonTopLevelInteractiveTUIMetadata() throws {
        let invalidRecords = [
            sessionMeta(source: "exec"),
            sessionMeta(originator: "codex-app"),
            sessionMeta(threadSource: "subagent")
        ]

        for record in invalidRecords {
            try writeLog([record])
            XCTAssertNil(try readSession())
        }
    }

    func testCompletedTaskIsStalled() throws {
        try writeLog([sessionMeta(), userMessage("task"), taskStarted(), taskComplete()])

        XCTAssertEqual(try XCTUnwrap(readSession()).activity, .stalled)
    }

    func testUnfinishedTaskAtFiveMinutesIsStalled() throws {
        try writeLog([sessionMeta(), userMessage("task"), taskStarted()])

        let snapshot = try XCTUnwrap(reader.readSession(
            at: logURL,
            sessionNames: [:],
            modifiedAt: try date("2026-07-20T06:00:00Z"),
            now: try date("2026-07-20T06:05:00Z")
        ))

        XCTAssertEqual(snapshot.activity, .stalled)
    }

    func testMalformedAndIncompleteLinesDoNotDiscardValidEvents() throws {
        let raw = [sessionMeta(), "{bad json", userMessage("task"), taskStarted()]
            .joined(separator: "\n") + "\n{\"partial\":"
        try raw.write(to: logURL, atomically: true, encoding: .utf8)

        let snapshot = try XCTUnwrap(readSession())

        XCTAssertEqual(snapshot.sessionID, "s1")
        XCTAssertEqual(snapshot.activity, .running)
    }

    func testDisplayDescriptionTruncatesAtSixtyCharactersWithoutBreakingUnicode() throws {
        let task = String(repeating: "任", count: 65)
        try writeLog([sessionMeta(), userMessage(task)])

        let snapshot = try XCTUnwrap(readSession())

        XCTAssertEqual(snapshot.taskDescription.count, 65)
        XCTAssertEqual(snapshot.displayTaskDescription.count, 60)
        XCTAssertEqual(snapshot.displayTaskDescription, String(repeating: "任", count: 60))
    }

    private func readSession() throws -> SessionLogSnapshot? {
        try reader.readSession(
            at: logURL,
            sessionNames: [:],
            modifiedAt: date("2026-07-20T06:01:00Z"),
            now: date("2026-07-20T06:02:00Z")
        )
    }

    private func writeLog(_ records: [String]) throws {
        try records.joined(separator: "\n").appending("\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func writeIndex(_ records: [String]) throws {
        try records.joined(separator: "\n").appending("\n")
            .write(to: indexURL, atomically: true, encoding: .utf8)
    }

    private func sessionMeta(
        cwd: String = "/tmp/work",
        source: String = "cli",
        originator: String = "codex-tui",
        threadSource: String = "user"
    ) -> String {
        """
        {"timestamp":"2026-07-20T06:00:00Z","type":"session_meta","payload":{"id":"s1","session_id":"s1","timestamp":"2026-07-20T06:00:00Z","cwd":"\(cwd)","source":"\(source)","originator":"\(originator)","thread_source":"\(threadSource)"}}
        """
    }

    private func userMessage(_ message: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "timestamp": "2026-07-20T06:00:10Z",
            "type": "event_msg",
            "payload": ["type": "user_message", "message": message]
        ])
        return String(decoding: data, as: UTF8.self)
    }

    private func taskStarted() -> String {
        #"{"timestamp":"2026-07-20T06:00:20Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#
    }

    private func taskComplete() -> String {
        #"{"timestamp":"2026-07-20T06:00:30Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}"#
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }
}

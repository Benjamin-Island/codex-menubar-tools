import Foundation
import XCTest
@testable import CodexSessionCore

final class SessionInventoryTests: XCTestCase {
    private var rootDirectory: URL!
    private var sessionsDirectory: URL!
    private var indexURL: URL!
    private var provider: MutableProcessProvider!
    private var now: Date!

    override func setUpWithError() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionInventoryTests-\(UUID().uuidString)")
        sessionsDirectory = rootDirectory.appendingPathComponent("sessions", isDirectory: true)
        indexURL = rootDirectory.appendingPathComponent("session_index.jsonl")
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        provider = MutableProcessProvider()
        now = try date("2026-07-20T06:10:00Z")
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
    }

    func testWritableOpenLogWinsForResumedOldSessionAndSameDirectoryProcesses() throws {
        let firstLog = try writeLog(
            id: "old-a",
            cwd: "/tmp/shared",
            metadataAt: "2026-07-19T01:00:00Z",
            task: "Alpha resumed",
            running: true
        )
        let secondLog = try writeLog(
            id: "old-b",
            cwd: "/tmp/shared",
            metadataAt: "2026-07-18T01:00:00Z",
            task: "Beta resumed",
            running: false
        )
        provider.result = .success([
            process(pid: 10, cwd: "/tmp/shared", startedAt: "2026-07-20T06:00:00Z", openLogs: [firstLog.path]),
            process(pid: 11, cwd: "/tmp/shared", startedAt: "2026-07-20T06:00:00Z", openLogs: [secondLog.path])
        ])

        let items = try snapshots(from: makeInventory())

        XCTAssertEqual(items.map(\.pid), [10, 11])
        XCTAssertEqual(items.map(\.sessionID), ["old-a", "old-b"])
        XCTAssertEqual(items.map(\.taskDescription), ["Alpha resumed", "Beta resumed"])
    }

    func testFallbackAcceptsExactCwdAt120SecondsAndSelectsClosestTimestamp() throws {
        _ = try writeLog(
            id: "later",
            cwd: "/tmp/project",
            metadataAt: "2026-07-20T06:01:40Z",
            task: "Later"
        )
        _ = try writeLog(
            id: "closest",
            cwd: "/tmp/project",
            metadataAt: "2026-07-20T06:00:20Z",
            task: "Closest"
        )
        _ = try writeLog(
            id: "boundary",
            cwd: "/tmp/boundary",
            metadataAt: "2026-07-20T06:02:00Z",
            task: "Boundary"
        )
        provider.result = .success([
            process(pid: 20, cwd: "/tmp/project", startedAt: "2026-07-20T06:00:00Z"),
            process(pid: 21, cwd: "/tmp/boundary", startedAt: "2026-07-20T06:00:00Z")
        ])

        let items = try snapshots(from: makeInventory())

        XCTAssertEqual(items.first(where: { $0.pid == 20 })?.sessionID, "closest")
        XCTAssertEqual(items.first(where: { $0.pid == 21 })?.sessionID, "boundary")
    }

    func testFallbackRejects121SecondsWrongCwdAndDoesNotDoubleAssign() throws {
        _ = try writeLog(
            id: "too-late",
            cwd: "/tmp/late",
            metadataAt: "2026-07-20T06:02:01Z",
            task: "Too late"
        )
        _ = try writeLog(
            id: "one-log",
            cwd: "/tmp/shared",
            metadataAt: "2026-07-20T06:00:10Z",
            task: "Only association"
        )
        _ = try writeLog(
            id: "wrong-cwd",
            cwd: "/tmp/not-the-same",
            metadataAt: "2026-07-20T06:00:05Z",
            task: "Wrong cwd"
        )
        provider.result = .success([
            process(pid: 30, cwd: "/tmp/late", startedAt: "2026-07-20T06:00:00Z"),
            process(pid: 31, cwd: "/tmp/shared", startedAt: "2026-07-20T06:00:00Z"),
            process(pid: 32, cwd: "/tmp/shared", startedAt: "2026-07-20T06:00:00Z"),
            process(pid: 33, cwd: "/tmp/exact", startedAt: "2026-07-20T06:00:00Z")
        ])

        let items = try snapshots(from: makeInventory())

        XCTAssertNil(items.first(where: { $0.pid == 30 })?.sessionID)
        XCTAssertEqual(items.filter { $0.sessionID == "one-log" }.count, 1)
        XCTAssertNil(items.first(where: { $0.pid == 33 })?.sessionID)
    }

    func testCachedAssociationSurvivesMissingOpenFileUntilPIDExits() throws {
        let log = try writeLog(
            id: "cached",
            cwd: "/tmp/original",
            metadataAt: "2026-07-20T06:00:10Z",
            task: "Cached task"
        )
        let inventory = makeInventory()
        provider.result = .success([
            process(pid: 40, cwd: "/tmp/original", startedAt: "2026-07-20T06:00:00Z", openLogs: [log.path])
        ])
        XCTAssertEqual(try snapshots(from: inventory).first?.sessionID, "cached")

        provider.result = .success([
            process(pid: 40, cwd: "/tmp/changed", startedAt: "2026-07-20T06:00:00Z")
        ])
        XCTAssertEqual(try snapshots(from: inventory).first?.sessionID, "cached")

        provider.result = .success([])
        XCTAssertTrue(try snapshots(from: inventory).isEmpty)
        provider.result = .success([
            process(pid: 40, cwd: "/tmp/changed", startedAt: "2026-07-20T06:08:00Z")
        ])
        XCTAssertNil(try snapshots(from: inventory).first?.sessionID)
    }

    func testRecycledPIDDoesNotReusePreviousProcessCache() throws {
        let log = try writeLog(
            id: "old-process",
            cwd: "/tmp/original",
            metadataAt: "2026-07-20T06:00:10Z",
            task: "Old process"
        )
        let inventory = makeInventory()
        provider.result = .success([
            process(pid: 41, cwd: "/tmp/original", startedAt: "2026-07-20T06:00:00Z", openLogs: [log.path])
        ])
        XCTAssertEqual(try snapshots(from: inventory).first?.sessionID, "old-process")

        provider.result = .success([
            process(pid: 41, cwd: "/tmp/new-process", startedAt: "2026-07-20T06:08:00Z")
        ])

        XCTAssertNil(try snapshots(from: inventory).first?.sessionID)
    }

    func testUnassociatedTUIRemainsVisibleAsStalledWithDirectoryFallback() throws {
        provider.result = .success([
            process(pid: 50, cwd: "/tmp/customer-api", startedAt: "2026-07-20T06:00:00Z")
        ])

        let item = try XCTUnwrap(snapshots(from: makeInventory()).first)

        XCTAssertNil(item.sessionID)
        XCTAssertEqual(item.activity, .stalled)
        XCTAssertEqual(item.taskDescription, "customer-api")
        XCTAssertEqual(item.workingDirectory, "/tmp/customer-api")
    }

    func testMissingWorkingDirectoryUsesExplicitFallbacks() throws {
        provider.result = .success([
            process(pid: 51, cwd: nil, startedAt: "2026-07-20T06:00:00Z")
        ])

        let item = try XCTUnwrap(snapshots(from: makeInventory()).first)

        XCTAssertEqual(item.taskDescription, "Codex CLI")
        XCTAssertEqual(item.workingDirectory, "未知工作目录")
        XCTAssertEqual(item.activity, .stalled)
    }

    func testUsesNamedTaskAndSortsRunningBeforeStalledThenByTaskAndPID() throws {
        let zebra = try writeLog(
            id: "zebra",
            cwd: "/tmp/zebra",
            metadataAt: "2026-07-20T06:00:01Z",
            task: "ignored",
            running: true
        )
        let alpha = try writeLog(
            id: "alpha",
            cwd: "/tmp/alpha",
            metadataAt: "2026-07-20T06:00:02Z",
            task: "ignored",
            running: true
        )
        let stalled = try writeLog(
            id: "stalled",
            cwd: "/tmp/stalled",
            metadataAt: "2026-07-20T06:00:03Z",
            task: "Bravo",
            running: false
        )
        try [
            #"{"id":"zebra","thread_name":"Zulu"}"#,
            #"{"id":"alpha","thread_name":"alpha"}"#
        ].joined(separator: "\n").appending("\n")
            .write(to: indexURL, atomically: true, encoding: .utf8)
        provider.result = .success([
            process(pid: 60, cwd: "/tmp/zebra", startedAt: "2026-07-20T06:00:00Z", openLogs: [zebra.path]),
            process(pid: 61, cwd: "/tmp/alpha", startedAt: "2026-07-20T06:00:00Z", openLogs: [alpha.path]),
            process(pid: 62, cwd: "/tmp/stalled", startedAt: "2026-07-20T06:00:00Z", openLogs: [stalled.path])
        ])

        let items = try snapshots(from: makeInventory())

        XCTAssertEqual(items.map(\.pid), [61, 60, 62])
        XCTAssertEqual(items.map(\.taskDescription), ["alpha", "Zulu", "Bravo"])
    }

    func testMissingSessionsDirectoryIsEmptyRatherThanFailure() throws {
        try FileManager.default.removeItem(at: sessionsDirectory)
        provider.result = .success([
            process(pid: 70, cwd: "/tmp/project", startedAt: "2026-07-20T06:00:00Z")
        ])

        let items = try snapshots(from: makeInventory())

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].sessionID)
    }

    func testProcessEnumerationFailureBecomesInventoryFailure() {
        provider.result = .failure(TestError.enumerationFailed)

        guard case let .failure(error) = makeInventory().read() else {
            return XCTFail("Expected inventory failure")
        }
        XCTAssertEqual(error.message, "无法扫描 Codex CLI 进程")
        XCTAssertFalse(error.detail?.isEmpty ?? true)
    }

    private func makeInventory() -> SessionInventory {
        SessionInventory(
            processProvider: provider,
            classifier: InteractiveTUIClassifier(),
            logReader: CodexSessionLogReader(),
            sessionsDirectory: sessionsDirectory,
            sessionIndexURL: indexURL,
            currentUID: 501,
            now: { [now] in now! }
        )
    }

    private func snapshots(from inventory: SessionInventory) throws -> [SessionDisplaySnapshot] {
        switch inventory.read() {
        case let .snapshots(items):
            return items
        case let .failure(error):
            throw error
        }
    }

    private func process(
        pid: Int32,
        cwd: String?,
        startedAt: String,
        openLogs: [String] = []
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            parentPID: 1,
            userID: 501,
            startedAt: try! date(startedAt),
            executablePath: "/opt/homebrew/bin/codex",
            arguments: ["codex"],
            workingDirectory: cwd,
            hasControllingTerminal: true,
            openFilePaths: openLogs
        )
    }

    @discardableResult
    private func writeLog(
        id: String,
        cwd: String,
        metadataAt: String,
        task: String,
        running: Bool = false
    ) throws -> URL {
        let directory = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("rollout-\(id).jsonl")
        let records = [
            json([
                "timestamp": metadataAt,
                "type": "session_meta",
                "payload": [
                    "id": id,
                    "session_id": id,
                    "timestamp": metadataAt,
                    "cwd": cwd,
                    "source": "cli",
                    "originator": "codex-tui",
                    "thread_source": "user"
                ]
            ]),
            json([
                "timestamp": metadataAt,
                "type": "event_msg",
                "payload": ["type": "user_message", "message": task]
            ])
        ] + (running ? [json([
            "timestamp": metadataAt,
            "type": "event_msg",
            "payload": ["type": "task_started", "turn_id": "turn-1"]
        ])] : [])
        try records.joined(separator: "\n").appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-30)],
            ofItemAtPath: url.path
        )
        return url
    }

    private func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }
}

private enum TestError: Error {
    case enumerationFailed
}

private final class MutableProcessProvider: ProcessProviding, @unchecked Sendable {
    var result: Result<[ProcessSnapshot], Error> = .success([])

    func processSnapshots() throws -> [ProcessSnapshot] {
        try result.get()
    }
}

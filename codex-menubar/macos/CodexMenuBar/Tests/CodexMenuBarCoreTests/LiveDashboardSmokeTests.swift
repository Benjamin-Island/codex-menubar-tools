import Darwin
import Foundation
import XCTest
@testable import CodexMenuBarCore

final class LiveDashboardSmokeTests: XCTestCase {
    func testTwoDashboardReadsDoNotMutateInjectedSessionTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadOnlyDashboardSmoke-\(UUID().uuidString)", isDirectory: true)
        let sessionsDirectory = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let logURL = sessionsDirectory.appendingPathComponent("rollout.jsonl")
        try Data(
            """
            {"timestamp":"2026-07-21T01:00:00Z","type":"session_meta","payload":{"id":"read-only","cwd":"/tmp/project","source":"cli"}}
            {"timestamp":"2026-07-21T01:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}}}}

            """.utf8
        ).write(to: logURL)
        let indexURL = root.appendingPathComponent("session_index.jsonl")
        try Data("{\"id\":\"read-only\",\"thread_name\":\"Read only\"}\n".utf8).write(to: indexURL)
        let reader = DashboardReader(
            logIndex: IncrementalCodexLogIndex(),
            historyAggregator: TokenHistoryAggregator(),
            rateLimitReducer: RateLimitReducer(),
            sessionInventory: SessionInventory(
                processProvider: NoProcesses(),
                classifier: InteractiveTUIClassifier(),
                currentUID: getuid()
            ),
            sessionsDirectory: sessionsDirectory,
            sessionIndexURL: indexURL,
            calendar: .current
        )

        let beforeFirstRead = try treeFingerprint(at: sessionsDirectory)
        _ = reader.read()
        _ = reader.read()
        let afterSecondRead = try treeFingerprint(at: sessionsDirectory)

        XCTAssertEqual(
            afterSecondRead,
            beforeFirstRead,
            "Dashboard reads must not mutate Codex session files"
        )
    }

    func testLiveDashboardReadIsReadOnlyAndReachesTerminalStates() throws {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw XCTSkip("No local Codex sessions directory")
        }

        let reader = DashboardReader(
            logIndex: IncrementalCodexLogIndex(),
            historyAggregator: TokenHistoryAggregator(),
            rateLimitReducer: RateLimitReducer(),
            sessionInventory: SessionInventory(
                processProvider: DarwinProcessProvider(sessionsDirectory: sessionsDirectory),
                classifier: InteractiveTUIClassifier(),
                currentUID: getuid()
            ),
            sessionsDirectory: sessionsDirectory,
            sessionIndexURL: codexDirectory.appendingPathComponent("session_index.jsonl"),
            calendar: .current
        )

        let startedAt = Date()
        let snapshot = reader.read()
        let finishedAt = Date()

        if case .loading = snapshot.rateLimit { XCTFail("Rate limit remained loading") }
        if case .loading = snapshot.history { XCTFail("History remained loading") }
        if case .loading = snapshot.sessions { XCTFail("Sessions remained loading") }
        XCTAssertGreaterThanOrEqual(snapshot.updatedAt, startedAt)
        XCTAssertLessThanOrEqual(snapshot.updatedAt, finishedAt)
    }

    private func treeFingerprint(at directory: URL) throws -> [ReadOnlyFileFingerprint] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [ReadOnlyFileFingerprint] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            result.append(ReadOnlyFileFingerprint(
                path: url.standardizedFileURL.path,
                byteSize: values.fileSize ?? 0,
                modifiedAt: values.contentModificationDate ?? .distantPast
            ))
        }
        return result.sorted { $0.path < $1.path }
    }
}

private struct ReadOnlyFileFingerprint: Equatable {
    let path: String
    let byteSize: Int
    let modifiedAt: Date
}

private struct NoProcesses: ProcessProviding {
    func processSnapshots() throws -> [ProcessSnapshot] { [] }
}

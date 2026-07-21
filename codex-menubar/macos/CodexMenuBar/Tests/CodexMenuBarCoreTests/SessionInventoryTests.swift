import Foundation
import XCTest
@testable import CodexMenuBarCore

final class SessionInventoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)

    func testWritableOpenLogWinsAndExposesIndexedDetails() throws {
        let first = log(
            id: "old-a",
            name: "Alpha resumed",
            cwd: "/tmp/shared",
            metadataAt: 1_000,
            modifiedAt: 1_980,
            running: true,
            totalTokens: 120
        )
        let second = log(
            id: "old-b",
            name: "Beta resumed",
            cwd: "/tmp/shared",
            metadataAt: 900,
            modifiedAt: 1_970,
            running: false,
            totalTokens: 80
        )
        let provider = MutableProcessProvider(.success([
            process(pid: 10, cwd: "/tmp/shared", startedAt: 1_900, openLogs: [first.path]),
            process(pid: 11, cwd: "/tmp/shared", startedAt: 1_900, openLogs: [second.path])
        ]))

        let items = try snapshots(from: SessionInventory(
            processProvider: provider,
            classifier: InteractiveTUIClassifier(),
            currentUID: 501
        ).read(summaries: [first, second], now: now))

        XCTAssertEqual(items.map(\.sessionID), ["old-a", "old-b"])
        XCTAssertEqual(items[0].sourcePath, first.path)
        XCTAssertEqual(items[0].lastUpdatedAt, first.modifiedAt)
        XCTAssertEqual(items[0].tokenCounts.total, 120)
        XCTAssertEqual(items[0].activity, .running)
    }

    func testFallbackUsesExactCWDZeroTo120SecondsAndClosestTimestamp() throws {
        let logs = [
            log(id: "later", cwd: "/tmp/project", metadataAt: 1_100),
            log(id: "closest", cwd: "/tmp/project", metadataAt: 1_020),
            log(id: "boundary", cwd: "/tmp/boundary", metadataAt: 1_120),
            log(id: "late", cwd: "/tmp/late", metadataAt: 1_121),
            log(id: "wrong", cwd: "/tmp/other", metadataAt: 1_005)
        ]
        let provider = MutableProcessProvider(.success([
            process(pid: 20, cwd: "/tmp/project", startedAt: 1_000),
            process(pid: 21, cwd: "/tmp/boundary", startedAt: 1_000),
            process(pid: 22, cwd: "/tmp/late", startedAt: 1_000),
            process(pid: 23, cwd: "/tmp/exact", startedAt: 1_000)
        ]))
        let inventory = SessionInventory(processProvider: provider, classifier: .init(), currentUID: 501)

        let items = try snapshots(from: inventory.read(summaries: logs, now: now))
        XCTAssertEqual(items.first { $0.pid == 20 }?.sessionID, "closest")
        XCTAssertEqual(items.first { $0.pid == 21 }?.sessionID, "boundary")
        XCTAssertNil(items.first { $0.pid == 22 }?.sessionID)
        XCTAssertNil(items.first { $0.pid == 23 }?.sessionID)
    }

    func testOneLogIsNotDoubleAssignedAndNonTUILogIsNeverAssociated() throws {
        let only = log(id: "one", cwd: "/tmp/shared", metadataAt: 1_010)
        let nonTUI = log(id: "exec", cwd: "/tmp/exec", metadataAt: 1_010, isTUI: false)
        let provider = MutableProcessProvider(.success([
            process(pid: 30, cwd: "/tmp/shared", startedAt: 1_000),
            process(pid: 31, cwd: "/tmp/shared", startedAt: 1_000),
            process(pid: 32, cwd: "/tmp/exec", startedAt: 1_000)
        ]))
        let inventory = SessionInventory(processProvider: provider, classifier: .init(), currentUID: 501)

        let items = try snapshots(from: inventory.read(summaries: [only, nonTUI], now: now))
        XCTAssertEqual(items.filter { $0.sessionID == "one" }.count, 1)
        XCTAssertNil(items.first { $0.pid == 32 }?.sessionID)
    }

    func testCachedAssociationSurvivesMissingOpenPathButNotExitOrRecycledPID() throws {
        let associated = log(id: "cached", cwd: "/tmp/original", metadataAt: 1_010)
        let provider = MutableProcessProvider(.success([
            process(pid: 40, cwd: "/tmp/original", startedAt: 1_000, openLogs: [associated.path])
        ]))
        let inventory = SessionInventory(processProvider: provider, classifier: .init(), currentUID: 501)
        XCTAssertEqual(try snapshots(from: inventory.read(summaries: [associated], now: now)).first?.sessionID, "cached")

        provider.result = .success([process(pid: 40, cwd: "/tmp/changed", startedAt: 1_000)])
        XCTAssertEqual(try snapshots(from: inventory.read(summaries: [associated], now: now)).first?.sessionID, "cached")

        provider.result = .success([])
        XCTAssertTrue(try snapshots(from: inventory.read(summaries: [associated], now: now)).isEmpty)
        provider.result = .success([process(pid: 40, cwd: "/tmp/changed", startedAt: 1_500)])
        XCTAssertNil(try snapshots(from: inventory.read(summaries: [associated], now: now)).first?.sessionID)
    }

    func testUnassociatedTUIStaysVisibleWithEnglishFallbacks() throws {
        let provider = MutableProcessProvider(.success([
            process(pid: 50, cwd: "/tmp/customer-api", startedAt: 1_000),
            process(pid: 51, cwd: nil, startedAt: 1_000)
        ]))
        let inventory = SessionInventory(processProvider: provider, classifier: .init(), currentUID: 501)
        let items = try snapshots(from: inventory.read(summaries: [], now: now))

        XCTAssertEqual(items.first { $0.pid == 50 }?.taskDescription, "customer-api")
        XCTAssertEqual(items.first { $0.pid == 50 }?.activity, .stalled)
        XCTAssertEqual(items.first { $0.pid == 50 }?.tokenCounts, .zero)
        XCTAssertEqual(items.first { $0.pid == 51 }?.taskDescription, "Codex CLI")
        XCTAssertEqual(items.first { $0.pid == 51 }?.workingDirectory, "Unknown working directory")
    }

    func testSortsRunningThenNameAndMapsProcessFailure() throws {
        let logs = [
            log(id: "z", name: "Zulu", cwd: "/z", metadataAt: 1_001, modifiedAt: 1_990, running: true),
            log(id: "a", name: "alpha", cwd: "/a", metadataAt: 1_002, modifiedAt: 1_990, running: true),
            log(id: "b", name: "Bravo", cwd: "/b", metadataAt: 1_003, modifiedAt: 1_000, running: true)
        ]
        let provider = MutableProcessProvider(.success([
            process(pid: 60, cwd: "/z", startedAt: 1_000, openLogs: [logs[0].path]),
            process(pid: 61, cwd: "/a", startedAt: 1_000, openLogs: [logs[1].path]),
            process(pid: 62, cwd: "/b", startedAt: 1_000, openLogs: [logs[2].path])
        ]))
        let inventory = SessionInventory(processProvider: provider, classifier: .init(), currentUID: 501)
        XCTAssertEqual(try snapshots(from: inventory.read(summaries: logs, now: now)).map(\.pid), [61, 60, 62])

        provider.result = .failure(InventoryTestError.enumeration)
        guard case let .failure(error) = inventory.read(summaries: logs, now: now) else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error.message, "Unable to scan Codex CLI processes")
    }

    func testActiveTaskAtExactlyFiveMinutesAndCompletedTaskAreStalled() throws {
        let exactBoundary = log(
            id: "boundary",
            cwd: "/boundary",
            metadataAt: 1_000,
            modifiedAt: 1_700,
            running: true
        )
        let completed = log(
            id: "completed",
            cwd: "/completed",
            metadataAt: 1_000,
            modifiedAt: 1_990,
            running: false
        )
        let provider = MutableProcessProvider(.success([
            process(pid: 70, cwd: "/boundary", startedAt: 1_000, openLogs: [exactBoundary.path]),
            process(pid: 71, cwd: "/completed", startedAt: 1_000, openLogs: [completed.path])
        ]))
        let inventory = SessionInventory(processProvider: provider, classifier: .init(), currentUID: 501)

        let items = try snapshots(from: inventory.read(summaries: [exactBoundary, completed], now: now))
        XCTAssertEqual(items.map(\.activity), [.stalled, .stalled])
    }

    private func snapshots(from result: SessionInventoryResult) throws -> [SessionDisplaySnapshot] {
        switch result {
        case let .snapshots(items): return items
        case let .failure(error): throw error
        }
    }

    private func process(
        pid: Int32,
        cwd: String?,
        startedAt: TimeInterval,
        openLogs: [String] = []
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            parentPID: 1,
            userID: 501,
            startedAt: Date(timeIntervalSince1970: startedAt),
            executablePath: "/opt/homebrew/bin/codex",
            arguments: ["codex"],
            workingDirectory: cwd,
            hasControllingTerminal: true,
            openFilePaths: openLogs
        )
    }

    private func log(
        id: String,
        name: String? = nil,
        cwd: String,
        metadataAt: TimeInterval,
        modifiedAt: TimeInterval = 1_980,
        running: Bool = false,
        totalTokens: Int64 = 0,
        isTUI: Bool = true
    ) -> SessionLogSummary {
        let path = "/sessions/\(id).jsonl"
        return SessionLogSummary(
            path: path,
            modifiedAt: Date(timeIntervalSince1970: modifiedAt),
            session: SessionIdentity(
                id: id,
                name: name ?? id,
                displayName: name ?? id,
                workingDirectory: cwd,
                sourceKind: isTUI ? "cli" : "exec"
            ),
            metadataTimestamp: Date(timeIntervalSince1970: metadataAt),
            dailyCounts: [:],
            latestTokenCounts: TokenCounts(total: totalTokens, input: 1, cachedInput: 2, output: 3, reasoning: 4),
            latestRateLimit: nil,
            lifecycle: running ? .active : .inactive,
            warnings: [],
            suppressedWarningCount: 0,
            isTopLevelInteractiveTUI: isTUI
        )
    }
}

private enum InventoryTestError: Error { case enumeration }

private final class MutableProcessProvider: ProcessProviding, @unchecked Sendable {
    var result: Result<[ProcessSnapshot], Error>
    init(_ result: Result<[ProcessSnapshot], Error>) { self.result = result }
    func processSnapshots() throws -> [ProcessSnapshot] { try result.get() }
}

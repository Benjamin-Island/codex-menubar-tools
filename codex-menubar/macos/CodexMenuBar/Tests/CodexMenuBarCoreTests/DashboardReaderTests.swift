import Foundation
import XCTest
@testable import CodexMenuBarCore

final class DashboardReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testProcessFailureDoesNotHideUsageOrHistory() {
        let reader = makeReader(
            indexResults: [.success(snapshot(summaries: [summary(hasRateLimit: true, totalTokens: 120)]))],
            processes: .failure(DashboardTestError.process)
        )

        let snapshot = reader.read()

        guard case .content = snapshot.rateLimit else { return XCTFail("Expected rate limit content") }
        guard case .content = snapshot.history else { return XCTFail("Expected history content") }
        guard case let .failure(error) = snapshot.sessions else { return XCTFail("Expected process failure") }
        XCTAssertEqual(error.message, "Unable to scan Codex CLI processes")
        XCTAssertFalse(error.detail?.isEmpty ?? true)
        XCTAssertEqual(snapshot.updatedAt, now)
    }

    func testDirectoryFailureStillShowsDiscoveredTUIAsUnassociated() {
        let reader = makeReader(
            indexResults: [.failure(DashboardTestError.directory)],
            processes: .success([makeProcess(pid: 42)])
        )

        let snapshot = reader.read()

        guard case .failure = snapshot.rateLimit else { return XCTFail("Expected rate limit failure") }
        guard case .failure = snapshot.history else { return XCTFail("Expected history failure") }
        guard case let .content(sessions) = snapshot.sessions else { return XCTFail("Expected session content") }
        XCTAssertEqual(sessions.map(\.pid), [42])
        XCTAssertNil(sessions[0].sessionID)
    }

    func testMissingEventsAndSessionsProduceIndependentEmptyStates() {
        let reader = makeReader(
            indexResults: [.success(snapshot(summaries: []))],
            processes: .success([])
        )
        let snapshot = reader.read()

        XCTAssertEqual(snapshot.rateLimit, .empty("No rate limit event found yet. Open or use Codex once to generate usage data."))
        XCTAssertEqual(snapshot.history, .empty("No Token history found yet."))
        XCTAssertEqual(snapshot.sessions, .empty("No active Codex sessions are running."))
    }

    func testRecentCodexDesktopSessionAppearsWithoutTUIProcess() {
        let desktop = summary(
            hasRateLimit: true,
            totalTokens: 420,
            sourceKind: "App",
            lifecycle: .active
        )
        let reader = makeReader(
            indexResults: [.success(snapshot(summaries: [desktop]))],
            processes: .success([])
        )

        let snapshot = reader.read()

        guard case let .content(sessions) = snapshot.sessions else {
            return XCTFail("Expected desktop session content")
        }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionID, desktop.session.id)
        XCTAssertEqual(sessions[0].activity, .running)
        XCTAssertLessThan(sessions[0].pid, 0)
        XCTAssertEqual(sessions[0].tokenCounts.total, 420)
    }

    func testRecentDesktopSessionSurvivesCLIProcessScanFailure() {
        let reader = makeReader(
            indexResults: [.success(snapshot(summaries: [
                summary(
                    hasRateLimit: false,
                    totalTokens: 8,
                    sourceKind: "App",
                    lifecycle: .inactive
                )
            ]))],
            processes: .failure(DashboardTestError.process)
        )

        let snapshot = reader.read()

        guard case let .content(sessions) = snapshot.sessions else {
            return XCTFail("Expected desktop fallback content")
        }
        XCTAssertEqual(sessions.first?.activity, .stalled)
    }

    func testDesktopSubagentDoesNotBecomeRunningUserTask() {
        let reader = makeReader(
            indexResults: [.success(snapshot(summaries: [
                summary(
                    hasRateLimit: false,
                    totalTokens: 8,
                    sourceKind: "Subagent",
                    lifecycle: .active
                )
            ]))],
            processes: .success([])
        )

        let snapshot = reader.read()

        XCTAssertEqual(
            snapshot.sessions,
            .empty("No active Codex sessions are running.")
        )
    }

    func testDesktopLogsKeepNewestLifecycleForSharedSession() {
        let sharedID = "desktop-thread"
        let reader = makeReader(
            indexResults: [.success(snapshot(summaries: [
                summary(
                    hasRateLimit: false,
                    totalTokens: 10,
                    sourceKind: "App",
                    sessionID: sharedID,
                    modifiedAt: now.addingTimeInterval(-60),
                    path: "/sessions/parent.jsonl"
                ),
                summary(
                    hasRateLimit: false,
                    totalTokens: 20,
                    sourceKind: "App",
                    lifecycle: .inactive,
                    sessionID: sharedID,
                    modifiedAt: now,
                    path: "/sessions/child.jsonl"
                )
            ]))],
            processes: .success([])
        )

        let snapshot = reader.read()

        guard case let .content(sessions) = snapshot.sessions else {
            return XCTFail("Expected deduplicated desktop session")
        }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionID, sharedID)
        XCTAssertEqual(sessions[0].activity, .stalled)
        XCTAssertEqual(sessions[0].tokenCounts.total, 20)
        XCTAssertEqual(sessions[0].sourcePath, "/sessions/child.jsonl")
    }

    func testIndexWarningLeavesGoodContentUsable() {
        let warning = ParseWarning(path: "/sessions/bad.jsonl", line: 0, message: "Unable to read log")
        let reader = makeReader(
            indexResults: [.success(snapshot(
                summaries: [summary(hasRateLimit: true, totalTokens: 50)],
                warnings: [warning]
            ))],
            processes: .success([])
        )

        let snapshot = reader.read()

        guard case .content = snapshot.rateLimit else { return XCTFail("Expected content") }
        guard case .content = snapshot.history else { return XCTFail("Expected content") }
        XCTAssertEqual(snapshot.warnings.map(\.path), [warning.path])
    }

    func testSuccessfulRefreshAfterDirectoryErrorUsesExactInjectedClock() {
        let index = DashboardIndexFake(results: [
            .failure(DashboardTestError.directory),
            .success(snapshot(summaries: [summary(hasRateLimit: true, totalTokens: 10)]))
        ])
        let reader = makeReader(index: index, processes: .success([]))

        guard case .failure = reader.read().history else { return XCTFail("Expected first failure") }
        let recovered = reader.read()
        guard case .content = recovered.history else { return XCTFail("Expected recovery") }
        XCTAssertEqual(recovered.updatedAt, now)
        XCTAssertEqual(index.modifiedSinceValues.last, utcCalendar().date(byAdding: .day, value: -59, to: utcCalendar().startOfDay(for: now)))
    }

    private func makeReader(
        indexResults: [Result<IncrementalLogIndexSnapshot, Error>],
        processes: Result<[ProcessSnapshot], Error>
    ) -> DashboardReader {
        makeReader(index: DashboardIndexFake(results: indexResults), processes: processes)
    }

    private func makeReader(
        index: DashboardIndexFake,
        processes: Result<[ProcessSnapshot], Error>
    ) -> DashboardReader {
        DashboardReader(
            logIndex: index,
            historyAggregator: TokenHistoryAggregator(),
            rateLimitReducer: RateLimitReducer(),
            sessionInventory: SessionInventory(
                processProvider: DashboardProcessFake(result: processes),
                classifier: InteractiveTUIClassifier(),
                currentUID: 501
            ),
            sessionsDirectory: URL(fileURLWithPath: "/sessions"),
            sessionIndexURL: URL(fileURLWithPath: "/session_index.jsonl"),
            calendar: utcCalendar(),
            now: { [now] in now }
        )
    }

    private func snapshot(
        summaries: [SessionLogSummary],
        warnings: [ParseWarning] = []
    ) -> IncrementalLogIndexSnapshot {
        IncrementalLogIndexSnapshot(summaries: summaries, warnings: warnings)
    }

    private func summary(
        hasRateLimit: Bool,
        totalTokens: Int64,
        sourceKind: String = "cli",
        lifecycle: LifecycleSummary = .active,
        sessionID: String? = nil,
        modifiedAt: Date? = nil,
        path: String = "/sessions/good.jsonl"
    ) -> SessionLogSummary {
        let fileModifiedAt = modifiedAt ?? now
        let counts = TokenCounts(total: totalTokens, input: totalTokens, cachedInput: 0, output: 0, reasoning: 0)
        let rate = hasRateLimit ? RateLimitCandidate(
            limitID: "codex",
            primary: RawRateLimitWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            credits: nil,
            planType: "plus",
            reportedAt: now,
            fileModifiedAt: fileModifiedAt,
            sequence: 1,
            sourcePath: path
        ) : nil
        return SessionLogSummary(
            path: path,
            modifiedAt: fileModifiedAt,
            session: SessionIdentity(
                id: sessionID ?? path,
                name: "Test session",
                displayName: "Test session",
                workingDirectory: "/tmp/project",
                sourceKind: sourceKind
            ),
            metadataTimestamp: fileModifiedAt,
            dailyCounts: totalTokens > 0 ? [utcCalendar().startOfDay(for: now): counts] : [:],
            latestTokenCounts: counts,
            latestRateLimit: rate,
            lifecycle: lifecycle,
            warnings: [],
            suppressedWarningCount: 0,
            isTopLevelInteractiveTUI: true
        )
    }

    private func makeProcess(pid: Int32) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            parentPID: 1,
            userID: 501,
            startedAt: now,
            executablePath: "/opt/homebrew/bin/codex",
            arguments: ["codex"],
            workingDirectory: "/tmp/project",
            hasControllingTerminal: true,
            openFilePaths: []
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private enum DashboardTestError: Error { case process, directory }

private final class DashboardIndexFake: IncrementalLogIndexing, @unchecked Sendable {
    var results: [Result<IncrementalLogIndexSnapshot, Error>]
    private(set) var modifiedSinceValues: [Date] = []

    init(results: [Result<IncrementalLogIndexSnapshot, Error>]) {
        self.results = results
    }

    func refresh(
        sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>,
        calendar: Calendar,
        now: Date,
        sessionIndexURL: URL?
    ) throws -> IncrementalLogIndexSnapshot {
        modifiedSinceValues.append(modifiedSince)
        return try results.removeFirst().get()
    }
}

private final class DashboardProcessFake: ProcessProviding, @unchecked Sendable {
    let result: Result<[ProcessSnapshot], Error>
    init(result: Result<[ProcessSnapshot], Error>) { self.result = result }
    func processSnapshots() throws -> [ProcessSnapshot] { try result.get() }
}

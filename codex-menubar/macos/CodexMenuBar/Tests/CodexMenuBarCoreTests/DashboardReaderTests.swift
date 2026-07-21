import Foundation
import XCTest
@testable import CodexMenuBarCore

final class DashboardReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testProcessFailureDoesNotHideUsageOrHistory() throws {
        let log = makeLog(path: "/sessions/good.jsonl", hasRateLimit: true, totalTokens: 120)
        let reader = makeReader(
            parsing: DashboardParsingFake(logs: [log.path: log]),
            discovery: DashboardDiscoveryFake(results: [[fingerprint(log)]]),
            processes: .failure(DashboardTestError.process)
        )

        let snapshot = reader.read()

        guard case .content = snapshot.rateLimit else { return XCTFail("Expected rate limit content") }
        guard case .content = snapshot.history else { return XCTFail("Expected history content") }
        guard case let .failure(error) = snapshot.sessions else {
            return XCTFail("Expected process failure")
        }
        XCTAssertEqual(error.message, "Unable to scan Codex CLI processes")
        XCTAssertFalse(error.detail?.isEmpty ?? true)
        XCTAssertEqual(snapshot.updatedAt, now)
    }

    func testDirectoryFailureStillShowsDiscoveredTUIAsUnassociated() {
        let process = makeProcess(pid: 42)
        let reader = makeReader(
            parsing: DashboardParsingFake(logs: [:]),
            discovery: DashboardDiscoveryFake(errors: [DashboardTestError.directory]),
            processes: .success([process])
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
            parsing: DashboardParsingFake(logs: [:]),
            discovery: DashboardDiscoveryFake(results: [[]]),
            processes: .success([])
        )
        let snapshot = reader.read()

        XCTAssertEqual(snapshot.rateLimit, .empty("No rate limit event found yet. Open or use Codex once to generate usage data."))
        XCTAssertEqual(snapshot.history, .empty("No Token history found yet."))
        XCTAssertEqual(snapshot.sessions, .empty("No interactive Codex TUI sessions are running."))
    }

    func testUnreadableFileAddsWarningWhileGoodContentRemainsUsable() {
        let good = makeLog(path: "/sessions/good.jsonl", hasRateLimit: true, totalTokens: 50)
        let bad = makeLog(path: "/sessions/bad.jsonl", hasRateLimit: false, totalTokens: 0)
        let parsing = DashboardParsingFake(logs: [good.path: good], failingPaths: [bad.path])
        let reader = makeReader(
            parsing: parsing,
            discovery: DashboardDiscoveryFake(results: [[fingerprint(good), fingerprint(bad)]]),
            processes: .success([])
        )

        let snapshot = reader.read()

        guard case .content = snapshot.rateLimit else { return XCTFail("Expected content") }
        guard case .content = snapshot.history else { return XCTFail("Expected content") }
        XCTAssertEqual(snapshot.warnings.map(\.path), [bad.path])
    }

    func testSuccessfulRefreshAfterDirectoryErrorUsesExactInjectedClock() {
        let log = makeLog(path: "/sessions/recovered.jsonl", hasRateLimit: true, totalTokens: 10)
        let discovery = DashboardDiscoveryFake(
            results: [[fingerprint(log)]],
            errors: [DashboardTestError.directory]
        )
        let reader = makeReader(
            parsing: DashboardParsingFake(logs: [log.path: log]),
            discovery: discovery,
            processes: .success([])
        )

        guard case .failure = reader.read().history else { return XCTFail("Expected first failure") }
        let recovered = reader.read()
        guard case .content = recovered.history else { return XCTFail("Expected recovery") }
        XCTAssertEqual(recovered.updatedAt, now)
    }

    private func makeReader(
        parsing: DashboardParsingFake,
        discovery: DashboardDiscoveryFake,
        processes: Result<[ProcessSnapshot], Error>
    ) -> DashboardReader {
        DashboardReader(
            logIndex: CodexLogIndex(parser: parsing, discoverer: discovery),
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

    private func fingerprint(_ log: IndexedSessionLog) -> LogFileFingerprint {
        LogFileFingerprint(path: log.path, modifiedAt: log.modifiedAt, byteSize: 100)
    }

    private func makeLog(path: String, hasRateLimit: Bool, totalTokens: Int64) -> IndexedSessionLog {
        let rateLimits = hasRateLimit ? [RateLimitCandidate(
            limitID: "codex",
            primary: RawRateLimitWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            credits: nil,
            planType: "plus",
            reportedAt: now,
            fileModifiedAt: now,
            sequence: 1,
            sourcePath: path
        )] : []
        return IndexedSessionLog(
            path: path,
            modifiedAt: now,
            session: SessionIdentity(
                id: path,
                name: "Test session",
                displayName: "Test session",
                workingDirectory: "/tmp/project",
                sourceKind: "cli"
            ),
            metadataTimestamp: now,
            tokenEvents: totalTokens > 0 ? [TokenEvent(
                timestamp: now,
                cumulative: TokenCounts(total: totalTokens, input: totalTokens, cachedInput: 0, output: 0, reasoning: 0),
                sequence: 1
            )] : [],
            rateLimits: rateLimits,
            lifecycle: .active,
            warnings: [],
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

private enum DashboardTestError: Error { case process, directory, file }

private final class DashboardParsingFake: LogParsing, @unchecked Sendable {
    let logs: [String: IndexedSessionLog]
    let failingPaths: Set<String>
    init(logs: [String: IndexedSessionLog], failingPaths: Set<String> = []) {
        self.logs = logs
        self.failingPaths = failingPaths
    }
    func parse(logURL: URL, sessionNames: [String: String], modifiedAt: Date) throws -> IndexedSessionLog {
        if failingPaths.contains(logURL.path) { throw DashboardTestError.file }
        return try XCTUnwrap(logs[logURL.path])
    }
    func readSessionNames(at indexURL: URL) throws -> [String: String] { [:] }
}

private final class DashboardDiscoveryFake: LogFileDiscovering, @unchecked Sendable {
    var results: [[LogFileFingerprint]]
    var errors: [Error]
    init(results: [[LogFileFingerprint]] = [], errors: [Error] = []) {
        self.results = results
        self.errors = errors
    }
    func discovery(in sessionsDirectory: URL, modifiedSince: Date, requiredPaths: Set<String>) throws -> LogDiscoverySnapshot {
        if !errors.isEmpty { throw errors.removeFirst() }
        return LogDiscoverySnapshot(fingerprints: results.removeFirst(), omittedFileCount: 0)
    }
}

private final class DashboardProcessFake: ProcessProviding, @unchecked Sendable {
    let result: Result<[ProcessSnapshot], Error>
    init(result: Result<[ProcessSnapshot], Error>) { self.result = result }
    func processSnapshots() throws -> [ProcessSnapshot] { try result.get() }
}

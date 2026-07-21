import XCTest
@testable import CodexMenuBarCore

final class CodexLogIndexTests: XCTestCase {
    func testSelectionKeepsNewestOrdinaryFilesAndEveryRequiredPath() {
        let ordinary = (0..<5).map {
            fingerprint("/sessions/\($0).jsonl", modified: TimeInterval($0), size: 10)
        }
        let live = fingerprint("/sessions/live.jsonl", modified: -1, size: 10)

        let output = LogFingerprintSelection.select(
            ordinary + [live],
            requiredPaths: [live.path],
            ordinaryLimit: 2
        )

        XCTAssertEqual(
            Set(output.fingerprints.map(\.path)),
            Set(["/sessions/3.jsonl", "/sessions/4.jsonl", live.path])
        )
        XCTAssertEqual(output.omittedFileCount, 3)
    }

    func testRefreshReusesUnchangedReparsesChangedAndRemovesDeletedFiles() throws {
        let parser = ParsingSpy()
        let discoverer = DiscoveryFake()
        let index = CodexLogIndex(parser: parser, discoverer: discoverer)
        let directory = URL(fileURLWithPath: "/sessions")
        let indexURL = URL(fileURLWithPath: "/session_index.jsonl")
        let a1 = fingerprint("/sessions/a.jsonl", modified: 1, size: 10)
        let b1 = fingerprint("/sessions/b.jsonl", modified: 1, size: 10)
        let b2 = fingerprint("/sessions/b.jsonl", modified: 2, size: 10)
        let b3 = fingerprint("/sessions/b.jsonl", modified: 2, size: 11)
        discoverer.results = [[a1, b1], [a1, b2], [a1, b3], [b3]]

        _ = try index.refresh(
            sessionsDirectory: directory,
            sessionIndexURL: indexURL,
            modifiedSince: .distantPast,
            requiredPaths: []
        )
        XCTAssertEqual(parser.parsedPaths, [a1.path, b1.path])

        _ = try index.refresh(
            sessionsDirectory: directory,
            sessionIndexURL: indexURL,
            modifiedSince: .distantPast,
            requiredPaths: []
        )
        XCTAssertEqual(parser.parsedPaths, [a1.path, b1.path, b2.path])

        _ = try index.refresh(
            sessionsDirectory: directory,
            sessionIndexURL: indexURL,
            modifiedSince: .distantPast,
            requiredPaths: []
        )
        XCTAssertEqual(parser.parsedPaths, [a1.path, b1.path, b2.path, b3.path])

        let final = try index.refresh(
            sessionsDirectory: directory,
            sessionIndexURL: indexURL,
            modifiedSince: .distantPast,
            requiredPaths: []
        )
        XCTAssertEqual(parser.parsedPaths, [a1.path, b1.path, b2.path, b3.path])
        XCTAssertEqual(final.logs.map(\.path), [b2.path])
        XCTAssertEqual(parser.sessionNameReadCount, 4)
    }

    func testSingleUnreadableFileProducesWarningWithoutDiscardingOtherLogs() throws {
        let parser = ParsingSpy()
        parser.failingPaths = ["/sessions/b.jsonl"]
        let discoverer = DiscoveryFake()
        discoverer.results = [[
            fingerprint("/sessions/a.jsonl", modified: 1, size: 10),
            fingerprint("/sessions/b.jsonl", modified: 1, size: 10)
        ]]
        let index = CodexLogIndex(parser: parser, discoverer: discoverer)

        let snapshot = try index.refresh(
            sessionsDirectory: URL(fileURLWithPath: "/sessions"),
            sessionIndexURL: URL(fileURLWithPath: "/session_index.jsonl"),
            modifiedSince: .distantPast,
            requiredPaths: []
        )

        XCTAssertEqual(snapshot.logs.map(\.path), ["/sessions/a.jsonl"])
        XCTAssertEqual(snapshot.warnings.map(\.path), ["/sessions/b.jsonl"])
        XCTAssertEqual(snapshot.warnings.first?.line, 0)
    }

    func testChangedFileFailureRetainsItsLastSuccessfulInMemoryLog() throws {
        let parser = ParsingSpy()
        let discoverer = DiscoveryFake()
        let first = fingerprint("/sessions/a.jsonl", modified: 1, size: 10)
        let changed = fingerprint("/sessions/a.jsonl", modified: 2, size: 10)
        discoverer.results = [[first], [changed]]
        let index = CodexLogIndex(parser: parser, discoverer: discoverer)
        let directory = URL(fileURLWithPath: "/sessions")
        let indexURL = URL(fileURLWithPath: "/session_index.jsonl")

        _ = try index.refresh(
            sessionsDirectory: directory,
            sessionIndexURL: indexURL,
            modifiedSince: .distantPast,
            requiredPaths: []
        )
        parser.failingPaths = [changed.path]
        let snapshot = try index.refresh(
            sessionsDirectory: directory,
            sessionIndexURL: indexURL,
            modifiedSince: .distantPast,
            requiredPaths: []
        )

        XCTAssertEqual(snapshot.logs.first?.modifiedAt, first.modifiedAt)
        XCTAssertEqual(snapshot.warnings.count, 1)
    }

    func testDiscoveryFailureThrowsInsteadOfClearingTheIndex() throws {
        let discoverer = DiscoveryFake()
        discoverer.error = TestError.denied
        let index = CodexLogIndex(parser: ParsingSpy(), discoverer: discoverer)

        XCTAssertThrowsError(try index.refresh(
            sessionsDirectory: URL(fileURLWithPath: "/denied"),
            sessionIndexURL: URL(fileURLWithPath: "/session_index.jsonl"),
            modifiedSince: .distantPast,
            requiredPaths: []
        )) { error in
            XCTAssertEqual(error as? TestError, .denied)
        }
    }

    func testNewIndexInstanceStartsWithNoCachedEntries() throws {
        let parser = ParsingSpy()
        let fingerprint = fingerprint("/sessions/a.jsonl", modified: 1, size: 10)
        let firstDiscovery = DiscoveryFake()
        firstDiscovery.results = [[fingerprint]]
        let secondDiscovery = DiscoveryFake()
        secondDiscovery.results = [[fingerprint]]

        _ = try CodexLogIndex(parser: parser, discoverer: firstDiscovery).refresh(
            sessionsDirectory: URL(fileURLWithPath: "/sessions"),
            sessionIndexURL: URL(fileURLWithPath: "/session_index.jsonl"),
            modifiedSince: .distantPast,
            requiredPaths: []
        )
        _ = try CodexLogIndex(parser: parser, discoverer: secondDiscovery).refresh(
            sessionsDirectory: URL(fileURLWithPath: "/sessions"),
            sessionIndexURL: URL(fileURLWithPath: "/session_index.jsonl"),
            modifiedSince: .distantPast,
            requiredPaths: []
        )

        XCTAssertEqual(parser.parsedPaths, [fingerprint.path, fingerprint.path])
    }

    func testRequiredOldFileIsDiscoveredAndMissingSessionIndexIsAllowed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let logURL = sessions.appendingPathComponent("old.jsonl")
        try "{\"type\":\"session_meta\",\"payload\":{\"id\":\"old\"}}\n"
            .data(using: .utf8)!
            .write(to: logURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: logURL.path
        )
        let discoverer = FileSystemLogDiscoverer()

        let excluded = try discoverer.discovery(
            in: sessions,
            modifiedSince: Date(timeIntervalSince1970: 200),
            requiredPaths: []
        )
        XCTAssertTrue(excluded.fingerprints.isEmpty)

        let index = CodexLogIndex(discoverer: discoverer)
        let snapshot = try index.refresh(
            sessionsDirectory: sessions,
            sessionIndexURL: root.appendingPathComponent("missing-session-index.jsonl"),
            modifiedSince: Date(timeIntervalSince1970: 200),
            requiredPaths: [logURL.path]
        )
        XCTAssertEqual(snapshot.logs.map(\.path), [logURL.path])
    }

    private func fingerprint(_ path: String, modified: TimeInterval, size: Int64) -> LogFileFingerprint {
        LogFileFingerprint(path: path, modifiedAt: Date(timeIntervalSince1970: modified), byteSize: size)
    }
}

private final class ParsingSpy: LogParsing, @unchecked Sendable {
    private(set) var parsedPaths: [String] = []
    private(set) var sessionNameReadCount = 0
    var failingPaths: Set<String> = []

    func parse(logURL: URL, sessionNames: [String: String], modifiedAt: Date) throws -> IndexedSessionLog {
        parsedPaths.append(logURL.path)
        if failingPaths.contains(logURL.path) { throw TestError.unreadable }
        return IndexedSessionLog(
            path: logURL.path,
            modifiedAt: modifiedAt,
            session: SessionIdentity(
                id: logURL.lastPathComponent,
                name: logURL.lastPathComponent,
                displayName: logURL.lastPathComponent,
                workingDirectory: nil,
                sourceKind: "Other"
            ),
            metadataTimestamp: nil,
            tokenEvents: [],
            rateLimits: [],
            lifecycle: .inactive,
            warnings: []
        )
    }

    func readSessionNames(at indexURL: URL) throws -> [String: String] {
        sessionNameReadCount += 1
        return [:]
    }
}

private final class DiscoveryFake: LogFileDiscovering, @unchecked Sendable {
    var results: [[LogFileFingerprint]] = []
    var error: Error?

    func discovery(
        in sessionsDirectory: URL,
        modifiedSince: Date,
        requiredPaths: Set<String>
    ) throws -> LogDiscoverySnapshot {
        if let error { throw error }
        return LogDiscoverySnapshot(
            fingerprints: results.removeFirst(),
            omittedFileCount: 0
        )
    }
}

private enum TestError: Error, Equatable {
    case denied
    case unreadable
}

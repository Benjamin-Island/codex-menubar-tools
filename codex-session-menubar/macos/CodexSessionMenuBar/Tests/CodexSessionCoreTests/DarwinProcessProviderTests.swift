import Foundation
import XCTest
@testable import CodexSessionCore

final class DarwinProcessProviderTests: XCTestCase {
    func testLiveProviderCanEnumerateCurrentMachine() {
        XCTAssertNoThrow(try DarwinProcessProvider().processSnapshots())
    }

    func testMapsProcessFieldsAndKeepsOnlyWritableSessionLogs() throws {
        let sessionsDirectory = URL(fileURLWithPath: "/Users/test/.codex/sessions")
        let reader = FakeDarwinProcessReader(
            pids: .success([42]),
            processes: [
                42: .success(
                    FakeDarwinProcess(
                        bsdInfo: DarwinBSDInfo(
                            pid: 42,
                            parentPID: 7,
                            userID: 501,
                            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                            hasControllingTerminal: true
                        ),
                        executablePath: "/opt/homebrew/bin/codex",
                        arguments: ["codex", "resume"],
                        workingDirectory: "/Users/test/project",
                        openFiles: [
                            DarwinOpenFile(
                                path: "/Users/test/.codex/sessions/2026/07/session-a.jsonl",
                                openFlags: O_WRONLY
                            ),
                            DarwinOpenFile(
                                path: "/Users/test/.codex/sessions/2026/07/session-b.jsonl",
                                openFlags: O_RDONLY
                            ),
                            DarwinOpenFile(
                                path: "/Users/test/.codex/sessions/2026/07/notes.txt",
                                openFlags: O_RDWR
                            ),
                            DarwinOpenFile(
                                path: "/Users/test/elsewhere/session-c.jsonl",
                                openFlags: O_RDWR
                            )
                        ]
                    )
                )
            ]
        )
        let provider = DarwinProcessProvider(reader: reader, sessionsDirectory: sessionsDirectory)

        let snapshots = try provider.processSnapshots()

        XCTAssertEqual(
            snapshots,
            [
                ProcessSnapshot(
                    pid: 42,
                    parentPID: 7,
                    userID: 501,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    executablePath: "/opt/homebrew/bin/codex",
                    arguments: ["codex", "resume"],
                    workingDirectory: "/Users/test/project",
                    hasControllingTerminal: true,
                    openFilePaths: ["/Users/test/.codex/sessions/2026/07/session-a.jsonl"]
                )
            ]
        )
    }

    func testSkipsProcessThatDisappearsDuringInspection() throws {
        let valid = FakeDarwinProcess(
            bsdInfo: DarwinBSDInfo(
                pid: 20,
                parentPID: 1,
                userID: 501,
                startedAt: Date(timeIntervalSince1970: 2_000),
                hasControllingTerminal: true
            ),
            executablePath: "/usr/local/bin/codex",
            arguments: ["codex"],
            workingDirectory: "/tmp/project",
            openFiles: []
        )
        let reader = FakeDarwinProcessReader(
            pids: .success([10, 20]),
            processes: [
                10: .failure(FakeError.processDisappeared),
                20: .success(valid)
            ]
        )
        let provider = DarwinProcessProvider(
            reader: reader,
            sessionsDirectory: URL(fileURLWithPath: "/Users/test/.codex/sessions")
        )

        let snapshots = try provider.processSnapshots()

        XCTAssertEqual(snapshots.map(\.pid), [20])
    }

    func testUsesArgumentZeroWhenExecutablePathIsUnavailable() throws {
        let reader = FakeDarwinProcessReader(
            pids: .success([42]),
            processes: [
                42: .success(FakeDarwinProcess(
                    bsdInfo: DarwinBSDInfo(
                        pid: 42,
                        parentPID: 7,
                        userID: 501,
                        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        hasControllingTerminal: true
                    ),
                    executablePath: "/stale/install/codex",
                    arguments: ["/stale/install/codex"],
                    workingDirectory: "/Users/test/project",
                    openFiles: []
                ))
            ],
            executablePathFailures: [42]
        )
        let provider = DarwinProcessProvider(
            reader: reader,
            sessionsDirectory: URL(fileURLWithPath: "/Users/test/.codex/sessions")
        )

        let snapshots = try provider.processSnapshots()

        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshot.pid, 42)
        XCTAssertEqual(snapshot.executablePath, "/stale/install/codex")
    }

    func testSkipsProcessWhenExecutablePathAndArgumentZeroAreUnavailable() throws {
        let reader = FakeDarwinProcessReader(
            pids: .success([42]),
            processes: [
                42: .success(FakeDarwinProcess(
                    bsdInfo: DarwinBSDInfo(
                        pid: 42,
                        parentPID: 7,
                        userID: 501,
                        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        hasControllingTerminal: true
                    ),
                    executablePath: "/stale/install/codex",
                    arguments: [],
                    workingDirectory: "/Users/test/project",
                    openFiles: []
                ))
            ],
            executablePathFailures: [42]
        )
        let provider = DarwinProcessProvider(
            reader: reader,
            sessionsDirectory: URL(fileURLWithPath: "/Users/test/.codex/sessions")
        )

        XCTAssertTrue(try provider.processSnapshots().isEmpty)
    }

    func testPropagatesTopLevelEnumerationFailure() {
        let reader = FakeDarwinProcessReader(
            pids: .failure(FakeError.enumerationFailed),
            processes: [:]
        )
        let provider = DarwinProcessProvider(
            reader: reader,
            sessionsDirectory: URL(fileURLWithPath: "/Users/test/.codex/sessions")
        )

        XCTAssertThrowsError(try provider.processSnapshots()) { error in
            XCTAssertEqual(error as? FakeError, .enumerationFailed)
        }
    }
}

private enum FakeError: Error, Equatable {
    case enumerationFailed
    case processDisappeared
    case executablePathUnavailable
}

private struct FakeDarwinProcess {
    let bsdInfo: DarwinBSDInfo
    let executablePath: String
    let arguments: [String]
    let workingDirectory: String?
    let openFiles: [DarwinOpenFile]
}

private final class FakeDarwinProcessReader: DarwinProcessReading, @unchecked Sendable {
    let pids: Result<[Int32], Error>
    let processes: [Int32: Result<FakeDarwinProcess, Error>]
    let executablePathFailures: Set<Int32>

    init(
        pids: Result<[Int32], Error>,
        processes: [Int32: Result<FakeDarwinProcess, Error>],
        executablePathFailures: Set<Int32> = []
    ) {
        self.pids = pids
        self.processes = processes
        self.executablePathFailures = executablePathFailures
    }

    func allPIDs() throws -> [Int32] {
        try pids.get()
    }

    func bsdInfo(pid: Int32) throws -> DarwinBSDInfo {
        try process(pid).bsdInfo
    }

    func executablePath(pid: Int32) throws -> String {
        if executablePathFailures.contains(pid) {
            throw FakeError.executablePathUnavailable
        }
        return try process(pid).executablePath
    }

    func arguments(pid: Int32) throws -> [String] {
        try process(pid).arguments
    }

    func workingDirectory(pid: Int32) throws -> String? {
        try process(pid).workingDirectory
    }

    func openFiles(pid: Int32) throws -> [DarwinOpenFile] {
        try process(pid).openFiles
    }

    private func process(_ pid: Int32) throws -> FakeDarwinProcess {
        guard let result = processes[pid] else {
            throw FakeError.processDisappeared
        }
        return try result.get()
    }
}

import Darwin
import Foundation
import XCTest
@testable import CodexMenuBarCore

final class DarwinProcessProviderTests: XCTestCase {
    func testLiveProviderCanEnumerateCurrentMachine() {
        XCTAssertNoThrow(try DarwinProcessProvider().processSnapshots())
    }

    func testMapsFieldsAndKeepsOnlyWritableSessionLogs() throws {
        let reader = FakeDarwinProcessReader(
            pids: .success([42]),
            processes: [42: .success(FakeDarwinProcess(
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
                    DarwinOpenFile(path: "/Users/test/.codex/sessions/a.jsonl", openFlags: O_WRONLY),
                    DarwinOpenFile(path: "/Users/test/.codex/sessions/b.jsonl", openFlags: O_RDONLY),
                    DarwinOpenFile(path: "/Users/test/.codex/sessions/notes.txt", openFlags: O_RDWR),
                    DarwinOpenFile(path: "/Users/test/elsewhere/c.jsonl", openFlags: O_RDWR)
                ]
            ))]
        )
        let provider = DarwinProcessProvider(
            reader: reader,
            sessionsDirectory: URL(fileURLWithPath: "/Users/test/.codex/sessions")
        )

        let snapshot = try XCTUnwrap(provider.processSnapshots().first)
        XCTAssertEqual(snapshot.pid, 42)
        XCTAssertEqual(snapshot.arguments, ["codex", "resume"])
        XCTAssertEqual(snapshot.openFilePaths, ["/Users/test/.codex/sessions/a.jsonl"])
    }

    func testDisappearingProcessIsSkippedAndTopLevelFailurePropagates() throws {
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
        let provider = DarwinProcessProvider(
            reader: FakeDarwinProcessReader(
                pids: .success([10, 20]),
                processes: [10: .failure(FakeProcessError.disappeared), 20: .success(valid)]
            ),
            sessionsDirectory: URL(fileURLWithPath: "/sessions")
        )
        XCTAssertEqual(try provider.processSnapshots().map(\.pid), [20])

        let failing = DarwinProcessProvider(
            reader: FakeDarwinProcessReader(pids: .failure(FakeProcessError.enumeration), processes: [:]),
            sessionsDirectory: URL(fileURLWithPath: "/sessions")
        )
        XCTAssertThrowsError(try failing.processSnapshots())
    }

    func testArgumentZeroFallbackAndEmptyArgumentSkip() throws {
        let process = FakeDarwinProcess(
            bsdInfo: DarwinBSDInfo(
                pid: 42,
                parentPID: 1,
                userID: 501,
                startedAt: .distantPast,
                hasControllingTerminal: true
            ),
            executablePath: "/stale/codex",
            arguments: ["/fallback/codex"],
            workingDirectory: nil,
            openFiles: []
        )
        let reader = FakeDarwinProcessReader(
            pids: .success([42]),
            processes: [42: .success(process)],
            executablePathFailures: [42]
        )
        let provider = DarwinProcessProvider(reader: reader, sessionsDirectory: URL(fileURLWithPath: "/sessions"))
        XCTAssertEqual(try provider.processSnapshots().first?.executablePath, "/fallback/codex")

        let emptyArguments = FakeDarwinProcess(
            bsdInfo: process.bsdInfo,
            executablePath: process.executablePath,
            arguments: [],
            workingDirectory: nil,
            openFiles: []
        )
        let emptyReader = FakeDarwinProcessReader(
            pids: .success([42]),
            processes: [42: .success(emptyArguments)],
            executablePathFailures: [42]
        )
        XCTAssertTrue(try DarwinProcessProvider(
            reader: emptyReader,
            sessionsDirectory: URL(fileURLWithPath: "/sessions")
        ).processSnapshots().isEmpty)
    }
}

private enum FakeProcessError: Error { case enumeration, disappeared, executablePath }

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

    func allPIDs() throws -> [Int32] { try pids.get() }
    func bsdInfo(pid: Int32) throws -> DarwinBSDInfo { try process(pid).bsdInfo }
    func executablePath(pid: Int32) throws -> String {
        if executablePathFailures.contains(pid) { throw FakeProcessError.executablePath }
        return try process(pid).executablePath
    }
    func arguments(pid: Int32) throws -> [String] { try process(pid).arguments }
    func workingDirectory(pid: Int32) throws -> String? { try process(pid).workingDirectory }
    func openFiles(pid: Int32) throws -> [DarwinOpenFile] { try process(pid).openFiles }
    private func process(_ pid: Int32) throws -> FakeDarwinProcess {
        guard let result = processes[pid] else { throw FakeProcessError.disappeared }
        return try result.get()
    }
}

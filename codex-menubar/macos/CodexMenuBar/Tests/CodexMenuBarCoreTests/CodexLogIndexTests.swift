import Foundation
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

        XCTAssertEqual(Set(output.fingerprints.map(\.path)), Set([
            "/sessions/3.jsonl", "/sessions/4.jsonl", live.path
        ]))
        XCTAssertEqual(output.omittedFileCount, 3)
    }

    func testRequiredOldFileIsDiscoveredAndMissingDirectoryErrorsAreExplicit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let logURL = sessions.appendingPathComponent("old.jsonl")
        try Data("{}\n".utf8).write(to: logURL)
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

        let required = try discoverer.discovery(
            in: sessions,
            modifiedSince: Date(timeIntervalSince1970: 200),
            requiredPaths: [logURL.path]
        )
        XCTAssertEqual(required.fingerprints.map(\.path), [logURL.path])

        XCTAssertThrowsError(try discoverer.discovery(
            in: root.appendingPathComponent("missing"),
            modifiedSince: .distantPast,
            requiredPaths: []
        )) { error in
            XCTAssertEqual(error as? LogDiscoveryError, .missingDirectory(root.appendingPathComponent("missing").path))
        }
    }

    func testDiscoveryOnlyVisitsDatePartitionsInThirtyDayWindow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let recentDirectory = sessions.appendingPathComponent("2026/07/21", isDirectory: true)
        let oldDirectory = sessions.appendingPathComponent("2026/06/21", isDirectory: true)
        try FileManager.default.createDirectory(at: recentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let recent = recentDirectory.appendingPathComponent("recent.jsonl")
        let old = oldDirectory.appendingPathComponent("old.jsonl")
        try Data("{}\n".utf8).write(to: recent)
        try Data("{}\n".utf8).write(to: old)
        let misleadinglyRecentMTime = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-21T12:00:00Z"))
        try FileManager.default.setAttributes([.modificationDate: misleadinglyRecentMTime], ofItemAtPath: old.path)

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-21T12:00:00Z"))
        let discoverer = FileSystemLogDiscoverer(
            calendar: utcCalendar(),
            now: { now }
        )
        let output = try discoverer.discovery(
            in: sessions,
            modifiedSince: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-22T00:00:00Z")),
            requiredPaths: []
        )

        XCTAssertEqual(output.fingerprints.map(\.path), [recent.path])
    }

    private func fingerprint(_ path: String, modified: TimeInterval, size: Int64) -> LogFileFingerprint {
        LogFileFingerprint(path: path, modifiedAt: Date(timeIntervalSince1970: modified), byteSize: size)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

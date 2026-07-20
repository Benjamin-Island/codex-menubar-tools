import Darwin
import Foundation
import XCTest
@testable import CodexSessionCore

final class LiveSessionInventorySmokeTests: XCTestCase {
    func testLiveInventoryContainsOnlyInteractiveTUIProcesses() throws {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        let provider = DarwinProcessProvider(sessionsDirectory: sessionsDirectory)
        let classifier = InteractiveTUIClassifier()
        let candidates = classifier.candidates(
            from: try provider.processSnapshots(),
            currentUID: getuid()
        )

        XCTAssertFalse(candidates.contains { process in
            process.arguments.contains("app-server")
        })
        guard !candidates.isEmpty else {
            throw XCTSkip("No live interactive Codex CLI TUI process")
        }

        let inventory = SessionInventory(
            processProvider: provider,
            classifier: classifier,
            logReader: CodexSessionLogReader(),
            sessionsDirectory: sessionsDirectory,
            sessionIndexURL: codexDirectory.appendingPathComponent("session_index.jsonl"),
            currentUID: getuid()
        )
        guard case let .snapshots(snapshots) = inventory.read() else {
            return XCTFail("Live inventory read failed")
        }

        let candidatePIDs = Set(candidates.map(\.pid))
        XCTAssertTrue(snapshots.allSatisfy { candidatePIDs.contains($0.pid) })
        for snapshot in snapshots {
            print("pid=\(snapshot.pid) activity=\(snapshot.activity.rawValue) cwd=\(snapshot.workingDirectory)")
        }
    }
}

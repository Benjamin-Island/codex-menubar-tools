import Darwin
import Foundation
import XCTest
@testable import CodexMenuBarCore

final class LiveDashboardSmokeTests: XCTestCase {
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
            logIndex: CodexLogIndex(),
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
}

import XCTest
import CodexMenuBarCore
@testable import CodexMenuBar

@MainActor
final class DashboardStoreTests: XCTestCase {
    func testOverlappingRefreshesCoalesceIntoOneFollowUpAndKeepOldSnapshotVisible() async throws {
        let initial = snapshot(at: 1)
        let first = snapshot(at: 2)
        let second = snapshot(at: 3)
        let reader = SuspendedDashboardReader()
        let store = DashboardStore(snapshot: initial, reader: { await reader.read() })

        store.refresh()
        store.refresh()
        store.refresh()
        try await waitUntil { await reader.callCount == 1 }
        XCTAssertTrue(store.isRefreshing)
        XCTAssertEqual(store.snapshot, initial)

        await reader.resumeNext(with: first)
        try await waitUntil { await reader.callCount == 2 }
        XCTAssertTrue(store.isRefreshing)
        XCTAssertEqual(store.snapshot, first)

        await reader.resumeNext(with: second)
        try await waitUntil { !store.isRefreshing }
        let callCount = await reader.callCount
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(store.snapshot, second)
    }

    func testCopyPathWritesSelectedWorkingDirectoryOnlyForMatchingSession() {
        let pasteboard = PasteboardSpy()
        let session = SessionDisplaySnapshot(
            pid: 42,
            sessionID: "session-1",
            activity: .running,
            taskDescription: "Task",
            displayTaskDescription: "Task",
            workingDirectory: "/tmp/project",
            sourcePath: "/sessions/one.jsonl",
            lastUpdatedAt: nil,
            tokenCounts: .zero
        )
        let store = DashboardStore(
            snapshot: DashboardSnapshot(
                rateLimit: .empty("No usage"),
                history: .empty("No history"),
                sessions: .content([session]),
                warnings: [],
                updatedAt: .distantPast
            ),
            reader: { DashboardSnapshot.loading(at: .distantPast) },
            pasteboard: pasteboard
        )

        store.showLiveSession(id: session.id)
        store.copySelectedSessionPath()
        XCTAssertEqual(pasteboard.values, ["/tmp/project"])

        store.showLiveSession(id: "missing")
        store.copySelectedSessionPath()
        XCTAssertEqual(pasteboard.values, ["/tmp/project"])
    }

    func testSelectsAndCopiesByStableSessionIDWhenPIDIsShared() {
        let pasteboard = PasteboardSpy()
        let first = SessionDisplaySnapshot(
            pid: 42,
            sessionID: "desktop-a",
            sourceKind: "App",
            activity: .running,
            taskDescription: "Alpha",
            displayTaskDescription: "Alpha",
            workingDirectory: "/tmp/alpha",
            sourcePath: "/sessions/alpha.jsonl",
            lastUpdatedAt: nil,
            tokenCounts: .zero
        )
        let second = SessionDisplaySnapshot(
            pid: 42,
            sessionID: "desktop-b",
            sourceKind: "App",
            activity: .running,
            taskDescription: "Beta",
            displayTaskDescription: "Beta",
            workingDirectory: "/tmp/beta",
            sourcePath: "/sessions/beta.jsonl",
            lastUpdatedAt: nil,
            tokenCounts: .zero
        )
        let store = DashboardStore(
            snapshot: DashboardSnapshot(
                rateLimit: .empty("No usage"),
                history: .empty("No history"),
                sessions: .content([first, second]),
                warnings: [],
                updatedAt: .distantPast
            ),
            reader: { DashboardSnapshot.loading(at: .distantPast) },
            pasteboard: pasteboard
        )

        store.showLiveSession(id: second.id)
        store.copySelectedSessionPath()

        XCTAssertEqual(store.selectedSessionID, second.id)
        XCTAssertEqual(pasteboard.values, ["/tmp/beta"])
    }

    private func snapshot(at timestamp: TimeInterval) -> DashboardSnapshot {
        DashboardSnapshot(
            rateLimit: .empty("No usage"),
            history: .empty("No history"),
            sessions: .empty("No sessions"),
            warnings: [],
            updatedAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            await Task.yield()
        }
        throw StoreTestError.timedOut
    }
}

private actor SuspendedDashboardReader {
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<DashboardSnapshot, Never>] = []

    func read() async -> DashboardSnapshot {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeNext(with snapshot: DashboardSnapshot) {
        continuations.removeFirst().resume(returning: snapshot)
    }
}

@MainActor
private final class PasteboardSpy: PasteboardWriting {
    private(set) var values: [String] = []
    func write(_ string: String) { values.append(string) }
}

private enum StoreTestError: Error { case timedOut }

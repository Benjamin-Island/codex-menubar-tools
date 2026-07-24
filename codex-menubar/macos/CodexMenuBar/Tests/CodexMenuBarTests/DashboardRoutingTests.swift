import XCTest
import CodexMenuBarCore
@testable import CodexMenuBar

@MainActor
final class DashboardRoutingTests: XCTestCase {
    func testRoutesOverviewDayHistoricalSessionBackAndLiveSession() {
        let store = DashboardStore(
            snapshot: snapshot(),
            reader: { DashboardSnapshot.loading(at: .distantPast) }
        )
        let date = Date(timeIntervalSince1970: 123)

        store.showHistory(date: date)
        XCTAssertEqual(store.selectedTab, .history)
        XCTAssertEqual(store.historySelection, .day(date))

        store.showHistoricalSession(date: date, sessionID: "session-1")
        XCTAssertEqual(store.historySelection, .session(date: date, sessionID: "session-1"))

        store.showDay(date)
        XCTAssertEqual(store.historySelection, .day(date))

        store.showLiveSession(id: "session-42")
        XCTAssertEqual(store.selectedTab, .sessions)
        XCTAssertEqual(store.selectedSessionID, "session-42")
    }

    private func snapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            rateLimit: .empty("No usage"),
            history: .empty("No history"),
            sessions: .empty("No sessions"),
            warnings: [],
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }
}

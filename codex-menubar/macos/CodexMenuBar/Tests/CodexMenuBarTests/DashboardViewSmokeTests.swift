import AppKit
import SwiftUI
import XCTest
import CodexMenuBarCore
@testable import CodexMenuBar

@MainActor
final class DashboardViewSmokeTests: XCTestCase {
    func testLoadingFullEmptyAndIndependentFailureStatesHaveFiniteLayout() {
        let states = [
            DashboardSnapshot.loading(at: Date(timeIntervalSince1970: 1)),
            fullSnapshot(),
            DashboardSnapshot(
                rateLimit: .empty("No usage"),
                history: .empty("No history"),
                sessions: .empty("No sessions"),
                warnings: [],
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            DashboardSnapshot(
                rateLimit: .content(usage()),
                history: .failure(DashboardError(message: "History unavailable", detail: "Permission denied")),
                sessions: .empty("No sessions"),
                warnings: [DashboardWarning(path: "/bad.jsonl", line: 4, message: "Malformed JSON")],
                updatedAt: Date(timeIntervalSince1970: 3)
            )
        ]

        for snapshot in states {
            let store = DashboardStore(
                snapshot: snapshot,
                reader: { DashboardSnapshot.loading(at: .distantPast) }
            )
            let controller = NSHostingController(rootView: DashboardView(store: store))
            controller.view.frame = CGRect(x: 0, y: 0, width: 620, height: 520)
            controller.view.layoutSubtreeIfNeeded()
            let size = controller.view.fittingSize
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
    }

    func testPetIslandHasFiniteLayoutWithAndWithoutPet() {
        let store = DashboardStore(
            snapshot: fullSnapshot(),
            reader: { DashboardSnapshot.loading(at: .distantPast) }
        )
        let defaults = UserDefaults(suiteName: "PetIslandViewSmokeTests")!
        defaults.removePersistentDomain(forName: "PetIslandViewSmokeTests")
        let preferences = PetIslandPreferences(pets: [], defaults: defaults)

        for isNotched in [false, true] {
            let controller = NSHostingController(
                rootView: PetIslandView(
                    store: store,
                    preferences: preferences,
                    isNotchedDisplay: isNotched,
                    openDashboard: {}
                )
            )
            controller.view.frame = CGRect(
                origin: .zero,
                size: PetIslandPlacement.panelSize
            )
            controller.view.layoutSubtreeIfNeeded()
            let size = controller.view.fittingSize
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
    }

    private func fullSnapshot() -> DashboardSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let days = (0..<60).map { offset in
            DailyUsage(
                date: start.addingTimeInterval(Double(offset * 86_400)),
                counts: TokenCounts(total: Int64(offset), input: 10, cachedInput: 2, output: 3, reasoning: 1),
                sessions: [],
                heatLevel: offset % 5,
                isFuture: false
            )
        }
        let history = TokenHistorySnapshot(
            interval: DateInterval(start: start, duration: 60 * 86_400),
            days: days,
            heatmapDays: days.map { HeatmapDay(date: $0.date, usage: $0) },
            selectedDefaultDate: days.last!.date
        )
        let session = SessionDisplaySnapshot(
            pid: 42,
            sessionID: "session-1",
            activity: .running,
            taskDescription: "Build the dashboard",
            displayTaskDescription: "Build the dashboard",
            workingDirectory: "/tmp/project",
            sourcePath: "/sessions/one.jsonl",
            lastUpdatedAt: start,
            tokenCounts: TokenCounts(total: 100, input: 70, cachedInput: 20, output: 30, reasoning: 4)
        )
        return DashboardSnapshot(
            rateLimit: .content(usage()),
            history: .content(history),
            sessions: .content([session]),
            warnings: [],
            updatedAt: start
        )
    }

    private func usage() -> UsageSnapshot {
        UsageSnapshot(
            primary: WindowUsage(label: "5h", usedPercent: 28, remainingPercent: 72, resetsAt: nil),
            secondary: WindowUsage(label: "7d", usedPercent: 40, remainingPercent: 60, resetsAt: nil),
            planType: "plus",
            creditsDescription: nil,
            reportedAt: nil,
            sourcePath: "/sessions/one.jsonl"
        )
    }
}

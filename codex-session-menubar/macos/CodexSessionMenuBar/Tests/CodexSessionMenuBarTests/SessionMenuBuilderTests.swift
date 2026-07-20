import AppKit
import CodexSessionCore
import XCTest
@testable import CodexSessionMenuBar

@MainActor
final class SessionMenuBuilderTests: XCTestCase {
    func testSingleSessionMenuContainsReadOnlyStatusAndPathRows() throws {
        let (builder, _) = makeBuilder()
        let fullTask = "Fix login tests with a complete description that is longer than sixty visible characters"
        let snapshot = SessionDisplaySnapshot(
            pid: 42,
            sessionID: "s1",
            activity: .running,
            taskDescription: fullTask,
            displayTaskDescription: String(fullTask.prefix(60)),
            workingDirectory: "/tmp/customer-api"
        )

        let menu = builder.makeMenu(result: .snapshots([snapshot]))

        XCTAssertEqual(menu.items[0].title, "Codex CLI Sessions")
        XCTAssertEqual(menu.items[1].title, "1 interactive TUI session")
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "运行中 — \(String(fullTask.prefix(60)))")
        XCTAssertNil(menu.items[3].action)
        XCTAssertNil(menu.items[3].target)
        XCTAssertEqual(menu.items[3].toolTip, fullTask)
        XCTAssertEqual(menu.items[4].title, "/tmp/customer-api")
        XCTAssertNil(menu.items[4].action)
        XCTAssertNil(menu.items[4].target)
        XCTAssertEqual(menu.items[4].toolTip, "/tmp/customer-api")
    }

    func testPluralSessionsKeepInputOrderAndLocalizedStates() {
        let (builder, _) = makeBuilder()
        let snapshots = [
            snapshot(pid: 1, activity: .running, task: "Alpha"),
            snapshot(pid: 2, activity: .stalled, task: "Beta")
        ]

        let menu = builder.makeMenu(result: .snapshots(snapshots))

        XCTAssertEqual(menu.items[1].title, "2 interactive TUI sessions")
        XCTAssertEqual(menu.items[3].title, "运行中 — Alpha")
        XCTAssertEqual(menu.items[5].title, "停滞 — Beta")
    }

    func testEmptyStateIsExplicit() {
        let (builder, _) = makeBuilder()
        let menu = builder.makeMenu(result: .snapshots([]))

        XCTAssertEqual(menu.items[0].title, "Codex CLI Sessions")
        XCTAssertEqual(menu.items[1].title, "No interactive Codex TUI sessions")
    }

    func testErrorStateIncludesRetryableMessageAndDetail() {
        let (builder, _) = makeBuilder()
        let menu = builder.makeMenu(result: .failure(SessionInventoryError(
            message: "无法扫描 Codex CLI 进程",
            detail: "Operation not permitted"
        )))

        XCTAssertEqual(menu.items[1].title, "无法扫描 Codex CLI 进程")
        XCTAssertEqual(menu.items[2].title, "Detail: Operation not permitted")
    }

    func testLoadingStateIsExplicit() {
        let (builder, _) = makeBuilder()
        let menu = builder.makeMenu(result: nil)

        XCTAssertEqual(menu.items[1].title, "Loading interactive Codex TUI sessions")
    }

    func testOnlyRefreshAndQuitHaveActions() {
        let (builder, target) = makeBuilder()
        let menu = builder.makeMenu(result: .snapshots([
            snapshot(pid: 1, activity: .running, task: "Task")
        ]))
        let actionable = menu.items.filter { $0.action != nil }

        XCTAssertEqual(actionable.map(\.title), ["Refresh", "Quit"])
        XCTAssertTrue(actionable.allSatisfy { $0.target === target })
    }

    private func makeBuilder() -> (SessionMenuBuilder, MenuTarget) {
        let target = MenuTarget()
        return (
            SessionMenuBuilder(
                target: target,
                refreshAction: #selector(MenuTarget.refresh),
                quitAction: #selector(MenuTarget.quit)
            ),
            target
        )
    }

    private func snapshot(
        pid: Int32,
        activity: SessionActivity,
        task: String
    ) -> SessionDisplaySnapshot {
        SessionDisplaySnapshot(
            pid: pid,
            sessionID: "s\(pid)",
            activity: activity,
            taskDescription: task,
            displayTaskDescription: task,
            workingDirectory: "/tmp/\(task.lowercased())"
        )
    }
}

@MainActor
private final class MenuTarget: NSObject {
    @objc func refresh() {}
    @objc func quit() {}
}

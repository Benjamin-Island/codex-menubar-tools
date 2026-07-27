import XCTest
import CodexMenuBarCore
@testable import CodexMenuBar

final class PetUsageBadgePresentationTests: XCTestCase {
    func testPrimaryAndSecondaryRemainInConfirmedOrder() {
        let presentation = PetUsageBadgePresentation.make(
            snapshot: snapshot(
                primary: usage(label: "5h", remaining: 72),
                secondary: usage(label: "7d", remaining: 60)
            ),
            language: .english
        )

        XCTAssertEqual(presentation.primaryText, "72%")
        XCTAssertEqual(presentation.secondaryText, "60%")
        XCTAssertEqual(presentation.primaryRemainingPercent, 72)
        XCTAssertEqual(presentation.primaryTone, .green)
    }

    func testMissingPrimaryNeverFallsBackToSecondary() {
        let presentation = PetUsageBadgePresentation.make(
            snapshot: snapshot(
                primary: nil,
                secondary: usage(label: "7d", remaining: 60)
            ),
            language: .english
        )

        XCTAssertEqual(presentation.primaryText, "--")
        XCTAssertEqual(presentation.secondaryText, "60%")
        XCTAssertNil(presentation.primaryRemainingPercent)
        XCTAssertEqual(presentation.primaryTone, .neutral)
    }

    func testNonContentUsageStatesUsePlaceholders() {
        for rateLimit in [
            ContentState<UsageSnapshot>.loading,
            .empty("No usage"),
            .failure(DashboardError(message: "Unavailable", detail: nil))
        ] {
            let presentation = PetUsageBadgePresentation.make(
                snapshot: DashboardSnapshot(
                    rateLimit: rateLimit,
                    history: .empty("No history"),
                    sessions: .empty("No sessions"),
                    warnings: [],
                    updatedAt: .distantPast
                ),
                language: .english
            )
            XCTAssertEqual(presentation.primaryText, "--")
            XCTAssertEqual(presentation.secondaryText, "--")
        }
    }

    func testTitlePrefersRunningThenRecentSessionAndLocalizesEmptyState() {
        let stalled = session(
            id: "stalled",
            activity: .stalled,
            title: "Recent task"
        )
        let running = session(
            id: "running",
            activity: .running,
            title: "Running task"
        )

        XCTAssertEqual(
            presentation(sessions: [stalled, running]).projectTitle,
            "Running task"
        )
        XCTAssertEqual(
            presentation(sessions: [stalled]).projectTitle,
            "Recent task"
        )
        XCTAssertEqual(
            presentation(sessions: []).projectTitle,
            "No active Codex tasks"
        )
        XCTAssertEqual(
            presentation(sessions: [], language: .simplifiedChinese)
                .projectTitle,
            "当前没有 Codex 任务"
        )
    }

    func testRunningCountUsesOnlyRunningSessionsAndLocalizesPlural() {
        let sessions = [
            session(id: "one", activity: .running, title: "One"),
            session(id: "two", activity: .running, title: "Two"),
            session(id: "three", activity: .stalled, title: "Three")
        ]

        XCTAssertEqual(
            presentation(sessions: [sessions[0]]).runningText,
            "1 task running"
        )
        XCTAssertEqual(
            presentation(sessions: sessions).runningText,
            "2 tasks running"
        )
        XCTAssertEqual(
            presentation(sessions: sessions, language: .simplifiedChinese)
                .runningText,
            "2 个运行中"
        )
    }

    func testUsageToneThresholdsMatchDashboardSemantics() {
        XCTAssertEqual(PetUsageBadgePresentation.tone(for: nil), .neutral)
        XCTAssertEqual(PetUsageBadgePresentation.tone(for: 0), .red)
        XCTAssertEqual(PetUsageBadgePresentation.tone(for: 10), .red)
        XCTAssertEqual(PetUsageBadgePresentation.tone(for: 11), .orange)
        XCTAssertEqual(PetUsageBadgePresentation.tone(for: 30), .orange)
        XCTAssertEqual(PetUsageBadgePresentation.tone(for: 31), .green)
    }

    private func presentation(
        sessions: [SessionDisplaySnapshot],
        language: AppDisplayLanguage = .english
    ) -> PetUsageBadgePresentation {
        PetUsageBadgePresentation.make(
            snapshot: snapshot(
                primary: usage(label: "5h", remaining: 72),
                secondary: usage(label: "7d", remaining: 60),
                sessions: sessions
            ),
            language: language
        )
    }

    private func snapshot(
        primary: WindowUsage?,
        secondary: WindowUsage?,
        sessions: [SessionDisplaySnapshot] = []
    ) -> DashboardSnapshot {
        DashboardSnapshot(
            rateLimit: .content(
                UsageSnapshot(
                    primary: primary,
                    secondary: secondary,
                    planType: nil,
                    creditsDescription: nil,
                    reportedAt: nil,
                    sourcePath: "/tmp/session.jsonl"
                )
            ),
            history: .empty("No history"),
            sessions: .content(sessions),
            warnings: [],
            updatedAt: .distantPast
        )
    }

    private func usage(label: String, remaining: Int) -> WindowUsage {
        WindowUsage(
            label: label,
            usedPercent: Double(100 - remaining),
            remainingPercent: remaining,
            resetsAt: nil
        )
    }

    private func session(
        id: String,
        activity: SessionActivity,
        title: String
    ) -> SessionDisplaySnapshot {
        SessionDisplaySnapshot(
            pid: 42,
            sessionID: id,
            activity: activity,
            taskDescription: title,
            displayTaskDescription: title,
            workingDirectory: "/tmp/project",
            sourcePath: "/tmp/\(id).jsonl",
            lastUpdatedAt: nil,
            tokenCounts: .zero
        )
    }
}

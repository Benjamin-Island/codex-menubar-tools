import XCTest
@testable import CodexMenuBar

final class PetUsageBadgeStateTests: XCTestCase {
    func testAnchorDiscoveryAndSafeClickOpenSummary() {
        XCTAssertEqual(
            PetUsageBadgeState.reduce(.hidden, event: .anchorFound),
            .badge
        )
        XCTAssertEqual(
            PetUsageBadgeState.reduce(
                .badge,
                event: .badgeClicked(summaryCanFit: true)
            ),
            .summary
        )
    }

    func testSummaryClosesForEveryConfirmedDismissalEvent() {
        for event in [
            PetUsageBadgeEvent.badgeClicked(summaryCanFit: true),
            .outsideClicked,
            .escapePressed,
            .movementStarted
        ] {
            XCTAssertEqual(
                PetUsageBadgeState.reduce(.summary, event: event),
                .badge
            )
        }
    }

    func testLossAndDisableHideEveryVisibleState() {
        for state in [
            PetUsageBadgeVisibility.badge,
            .summary
        ] {
            XCTAssertEqual(
                PetUsageBadgeState.reduce(state, event: .anchorLost),
                .hidden
            )
            XCTAssertEqual(
                PetUsageBadgeState.reduce(state, event: .disabled),
                .hidden
            )
        }
    }

    func testUnsafeSummaryClickKeepsBadgeVisible() {
        XCTAssertEqual(
            PetUsageBadgeState.reduce(
                .badge,
                event: .badgeClicked(summaryCanFit: false)
            ),
            .badge
        )
    }
}

import XCTest
@testable import CodexMenuBar

final class StatusItemPresentationTests: XCTestCase {
    func testBuildsCombinedUsageAndSessionPresentation() {
        XCTAssertEqual(
            StatusItemPresentation.make(remainingPercent: 72, sessionCount: 3),
            StatusItemPresentation(
                usageLabel: "72",
                progress: 0.72,
                sessionLabel: "3",
                accessibilityValue: "72 percent remaining, 3 interactive sessions"
            )
        )
    }

    func testMissingErrorClampAndZeroSessions() {
        XCTAssertEqual(
            StatusItemPresentation.make(remainingPercent: nil, sessionCount: 0),
            .init(
                usageLabel: "--",
                progress: nil,
                sessionLabel: "0",
                accessibilityValue: "Usage unavailable, 0 interactive sessions"
            )
        )
        XCTAssertEqual(
            StatusItemPresentation.make(remainingPercent: nil, sessionCount: 1, hasUsageError: true),
            .init(
                usageLabel: "!",
                progress: nil,
                sessionLabel: "1",
                accessibilityValue: "Usage error, 1 interactive session"
            )
        )
        XCTAssertEqual(StatusItemPresentation.make(remainingPercent: -10, sessionCount: -1).progress, 0)
        XCTAssertEqual(StatusItemPresentation.make(remainingPercent: 120, sessionCount: 2).progress, 1)
        XCTAssertEqual(StatusItemPresentation.make(remainingPercent: 120, sessionCount: 2).usageLabel, "100")
        XCTAssertEqual(StatusItemPresentation.make(remainingPercent: 50, sessionCount: -1).sessionLabel, "0")
    }
}

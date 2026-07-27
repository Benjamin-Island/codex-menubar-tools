import CoreGraphics
import XCTest
@testable import CodexMenuBar

final class PetUsageBadgePlacementTests: XCTestCase {
    func testConvertsQuartzTopOriginToAppKitBottomOrigin() {
        let frame = PetUsageBadgePlacement.appKitFrame(
            from: CGRect(x: 100, y: 100, width: 200, height: 100),
            quartzScreenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            appKitScreenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 700, width: 200, height: 100))
    }

    func testConversionPreservesPerDisplayOffsetsAndNegativeCoordinates() {
        let frame = PetUsageBadgePlacement.appKitFrame(
            from: CGRect(x: -1_100, y: 1_000, width: 200, height: 100),
            quartzScreenFrame: CGRect(
                x: -1_200,
                y: 900,
                width: 1_200,
                height: 800
            ),
            appKitScreenFrame: CGRect(
                x: -1_200,
                y: -800,
                width: 1_200,
                height: 800
            )
        )

        XCTAssertEqual(frame, CGRect(x: -1_100, y: -200, width: 200, height: 100))
    }

    func testBadgeUsesRightBottomThenAvoidsObstacleOnTheLeft() throws {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)
        let visible = CGRect(x: 0, y: 0, width: 400, height: 400)

        let right = try XCTUnwrap(
            PetUsageBadgePlacement.badgeFrame(
                anchorFrame: anchor,
                obstacleFrames: [],
                visibleFrame: visible,
                previousFrame: nil
            )
        )
        XCTAssertEqual(right, CGRect(x: 208, y: 100, width: 48, height: 28))

        let left = try XCTUnwrap(
            PetUsageBadgePlacement.badgeFrame(
                anchorFrame: anchor,
                obstacleFrames: [right.insetBy(dx: -1, dy: -1)],
                visibleFrame: visible,
                previousFrame: nil
            )
        )
        XCTAssertEqual(left, CGRect(x: 44, y: 100, width: 48, height: 28))
    }

    func testBadgePrefersSafeCandidateNearestPreviousFrame() throws {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)
        let previous = CGRect(x: 44, y: 100, width: 48, height: 28)

        let result = try XCTUnwrap(
            PetUsageBadgePlacement.badgeFrame(
                anchorFrame: anchor,
                obstacleFrames: [],
                visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 400),
                previousFrame: previous
            )
        )

        XCTAssertEqual(result, previous)
    }

    func testBadgeReturnsNilWhenEveryCandidateIsUnsafe() {
        let anchor = CGRect(x: 20, y: 20, width: 60, height: 60)
        let visible = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertNil(
            PetUsageBadgePlacement.badgeFrame(
                anchorFrame: anchor,
                obstacleFrames: [],
                visibleFrame: visible,
                previousFrame: nil
            )
        )
    }

    func testSummaryExpandsAwayFromPetWithoutChangingBadgeFrame() throws {
        let anchor = CGRect(x: 100, y: 100, width: 100, height: 100)
        let badge = CGRect(x: 208, y: 100, width: 48, height: 28)
        let originalBadge = badge

        let summary = try XCTUnwrap(
            PetUsageBadgePlacement.summaryFrame(
                badgeFrame: badge,
                anchorFrame: anchor,
                obstacleFrames: [],
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 500)
            )
        )

        XCTAssertEqual(badge, originalBadge)
        XCTAssertEqual(summary.size, PetUsageBadgePlacement.summarySize)
        XCTAssertFalse(summary.intersects(anchor))
        XCTAssertFalse(summary.intersects(badge))
    }

    func testSummaryReturnsNilWhenNoCandidateFits() {
        XCTAssertNil(
            PetUsageBadgePlacement.summaryFrame(
                badgeFrame: CGRect(x: 208, y: 100, width: 48, height: 28),
                anchorFrame: CGRect(x: 100, y: 100, width: 100, height: 100),
                obstacleFrames: [],
                visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 150)
            )
        )
    }
}

import AppKit
import XCTest
@testable import CodexMenuBar

final class PetIslandPlacementTests: XCTestCase {
    func testFloatingPetUsesVisibleTopRightCorner() {
        let visible = NSRect(x: 0, y: 80, width: 1_920, height: 970)
        let frame = PetIslandPlacement.frame(
            expanded: false,
            visibleFrame: visible
        )

        XCTAssertEqual(frame.maxX, visible.maxX - 14)
        XCTAssertEqual(frame.maxY, visible.maxY - 10)
        XCTAssertEqual(frame.size, PetIslandPlacement.floatingSize)
    }

    func testPeekingPetUsesCompactEdgeSize() {
        let size = PetIslandPlacement.size(
            expanded: false,
            peeking: true,
            petScale: 3
        )

        XCTAssertEqual(size, PetIslandPlacement.peekSize)
    }

    func testThreeHundredPercentPetExpandsFloatingAndExpandedWindows() {
        XCTAssertEqual(
            PetIslandPlacement.size(expanded: false, petScale: 3),
            NSSize(width: 324, height: 288)
        )
        XCTAssertEqual(
            PetIslandPlacement.size(expanded: true, petScale: 3),
            NSSize(width: 410, height: 536)
        )
    }

    func testFloatingPlacementSupportsSecondaryScreenCoordinates() {
        let secondaryVisible = NSRect(x: 1_470, y: 254, width: 1_280, height: 776)
        let frame = PetIslandPlacement.frame(
            expanded: false,
            visibleFrame: secondaryVisible
        )

        XCTAssertGreaterThanOrEqual(frame.minX, secondaryVisible.minX)
        XCTAssertLessThanOrEqual(frame.maxX, secondaryVisible.maxX)
        XCTAssertGreaterThanOrEqual(frame.minY, secondaryVisible.minY)
        XCTAssertLessThanOrEqual(frame.maxY, secondaryVisible.maxY)
    }
}

import AppKit
import XCTest
@testable import CodexMenuBar

final class PetIslandPlacementTests: XCTestCase {
    func testCollapsedNotchStaysInsideMenuBarPlane() {
        let screen = NSRect(x: 1_920, y: -180, width: 2_560, height: 1_440)
        let visible = NSRect(x: 1_920, y: -180, width: 2_560, height: 1_406)
        let frame = PetIslandPlacement.frame(
            mode: .notch,
            expanded: false,
            screenFrame: screen,
            visibleFrame: visible,
            menuBarHeight: 34
        )

        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.height, 34)
        XCTAssertEqual(frame.width, PetIslandPlacement.notchWidth)
    }

    func testFloatingPetUsesVisibleTopRightCorner() {
        let screen = NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let visible = NSRect(x: 0, y: 80, width: 1_920, height: 970)
        let frame = PetIslandPlacement.frame(
            mode: .floating,
            expanded: false,
            screenFrame: screen,
            visibleFrame: visible,
            menuBarHeight: 30
        )

        XCTAssertEqual(frame.maxX, visible.maxX - 14)
        XCTAssertEqual(frame.maxY, visible.maxY - 10)
        XCTAssertEqual(frame.size, PetIslandPlacement.floatingSize)
    }

    func testPeekingPetUsesCompactEdgeSize() {
        let size = PetIslandPlacement.size(
            mode: .floating,
            expanded: false,
            menuBarHeight: 30,
            peeking: true
        )

        XCTAssertEqual(size, PetIslandPlacement.peekSize)
    }

    func testFloatingPlacementSupportsSecondaryScreenCoordinates() {
        let secondaryScreen = NSRect(x: 1_470, y: 254, width: 1_280, height: 800)
        let secondaryVisible = NSRect(x: 1_470, y: 254, width: 1_280, height: 776)
        let frame = PetIslandPlacement.frame(
            mode: .floating,
            expanded: false,
            screenFrame: secondaryScreen,
            visibleFrame: secondaryVisible,
            menuBarHeight: 24
        )

        XCTAssertGreaterThanOrEqual(frame.minX, secondaryVisible.minX)
        XCTAssertLessThanOrEqual(frame.maxX, secondaryVisible.maxX)
        XCTAssertGreaterThanOrEqual(frame.minY, secondaryVisible.minY)
        XCTAssertLessThanOrEqual(frame.maxY, secondaryVisible.maxY)
    }
}

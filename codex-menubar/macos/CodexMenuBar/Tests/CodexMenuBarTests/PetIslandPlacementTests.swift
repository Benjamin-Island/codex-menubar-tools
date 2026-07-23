import AppKit
import XCTest
@testable import CodexMenuBar

final class PetIslandPlacementTests: XCTestCase {
    func testCentersPanelAgainstTopEdgeForAnyDisplayOrigin() {
        let screen = NSRect(x: 1_920, y: -180, width: 2_560, height: 1_440)
        let size = PetIslandPlacement.panelSize

        let frame = PetIslandPlacement.frame(in: screen, size: size)

        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.size, size)
    }
}

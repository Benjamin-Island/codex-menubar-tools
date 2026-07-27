import XCTest
@testable import CodexMenuBar

final class ScreenCapturePermissionResetterTests: XCTestCase {
    func testCodexMenuBarCommandTargetsOnlyItsScreenCaptureRecord() {
        let command = ScreenCapturePermissionResetCommand.codexMenuBar

        XCTAssertEqual(command.executableURL.path, "/usr/bin/tccutil")
        XCTAssertEqual(
            command.arguments,
            [
                "reset",
                "ScreenCapture",
                "dev.benjamin.codex-menubar"
            ]
        )
    }

    func testExitStatusMapsZeroToSuccessAndNonzeroToFailure() {
        XCTAssertNil(
            ScreenCapturePermissionResetError.from(exitStatus: 0)
        )
        XCTAssertEqual(
            ScreenCapturePermissionResetError.from(exitStatus: 1),
            .nonzeroExit(1)
        )
    }
}

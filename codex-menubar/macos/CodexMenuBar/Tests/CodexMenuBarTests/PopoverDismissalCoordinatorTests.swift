import XCTest
@testable import CodexMenuBar

@MainActor
final class PopoverDismissalCoordinatorTests: XCTestCase {
    func testOutsideClickRequestsCloseWhileMonitoring() {
        let source = FakeOutsideClickEventSource()
        var closeCount = 0
        let coordinator = PopoverDismissalCoordinator(eventSource: source) {
            closeCount += 1
        }

        coordinator.start()
        source.sendOutsideClick()

        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(closeCount, 1)
    }

    func testStopRemovesMonitorAndPreventsLaterClose() {
        let source = FakeOutsideClickEventSource()
        var closeCount = 0
        let coordinator = PopoverDismissalCoordinator(eventSource: source) {
            closeCount += 1
        }
        coordinator.start()

        coordinator.stop()
        source.sendOutsideClick()

        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(closeCount, 0)
    }
}

@MainActor
private final class FakeOutsideClickEventSource: OutsideClickEventSource {
    private var handler: (@MainActor @Sendable () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(handler: @escaping @MainActor @Sendable () -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func sendOutsideClick() {
        handler?()
    }
}

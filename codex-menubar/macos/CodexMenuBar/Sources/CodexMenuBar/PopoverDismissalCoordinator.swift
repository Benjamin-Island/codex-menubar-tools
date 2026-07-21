import AppKit

@MainActor
protocol OutsideClickEventSource: AnyObject {
    func start(handler: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

@MainActor
final class GlobalMouseDownEventSource: OutsideClickEventSource {
    private var monitor: Any?

    func start(handler: @escaping @MainActor @Sendable () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in handler() }
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

@MainActor
final class PopoverDismissalCoordinator {
    private let eventSource: any OutsideClickEventSource
    private let closePopover: @MainActor @Sendable () -> Void

    init(
        eventSource: any OutsideClickEventSource,
        closePopover: @escaping @MainActor @Sendable () -> Void
    ) {
        self.eventSource = eventSource
        self.closePopover = closePopover
    }

    func start() {
        eventSource.start { [weak self] in
            self?.closePopover()
        }
    }

    func stop() {
        eventSource.stop()
    }
}

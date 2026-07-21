import AppKit
import Combine
import SwiftUI
import CodexMenuBarCore

@MainActor
final class StatusController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: DashboardStore
    private let sessionsDirectory: URL
    private let renderer: StatusItemRenderer
    private var cancellables: Set<AnyCancellable> = []
    private var monitor: SessionDirectoryMonitor?
    private var refreshTimer: Timer?

    init(
        store: DashboardStore,
        sessionsDirectory: URL,
        renderer: StatusItemRenderer = StatusItemRenderer()
    ) {
        self.store = store
        self.sessionsDirectory = sessionsDirectory
        self.renderer = renderer
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func start() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 620, height: 520)
        popover.contentViewController = NSHostingController(rootView: DashboardView(store: store))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Codex Menu Bar")
        }
        store.$snapshot
            .sink { [weak self] snapshot in self?.apply(snapshot) }
            .store(in: &cancellables)
        apply(store.snapshot)
        ensureMonitor()
        store.refresh()

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.ensureMonitor()
                self?.store.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            store.refresh()
        }
    }

    private func ensureMonitor() {
        guard monitor == nil else { return }
        let candidate = SessionDirectoryMonitor(directory: sessionsDirectory) { [weak self] in
            self?.store.refresh()
        }
        guard candidate.start() else { return }
        monitor = candidate
    }

    private func apply(_ snapshot: DashboardSnapshot) {
        let remainingPercent: Int?
        let hasUsageError: Bool
        switch snapshot.rateLimit {
        case let .content(usage):
            remainingPercent = usage.primary?.remainingPercent
            hasUsageError = false
        case .failure:
            remainingPercent = nil
            hasUsageError = true
        case .loading, .empty:
            remainingPercent = nil
            hasUsageError = false
        }
        let sessionCount: Int
        if case let .content(sessions) = snapshot.sessions {
            sessionCount = sessions.count
        } else {
            sessionCount = 0
        }
        let presentation = StatusItemPresentation.make(
            remainingPercent: remainingPercent,
            sessionCount: sessionCount,
            hasUsageError: hasUsageError
        )
        statusItem.button?.image = renderer.image(for: presentation)
        statusItem.button?.toolTip = presentation.accessibilityValue
        statusItem.button?.setAccessibilityValue(presentation.accessibilityValue)
    }
}

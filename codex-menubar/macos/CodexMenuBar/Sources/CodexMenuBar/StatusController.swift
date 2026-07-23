import AppKit
import Combine
import SwiftUI
import CodexMenuBarCore

@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: DashboardStore
    private let sessionsDirectory: URL
    private let renderer: StatusItemRenderer
    private let outsideClickEventSource: any OutsideClickEventSource
    private let petIslandPreferences: PetIslandPreferences
    private var cancellables: Set<AnyCancellable> = []
    private var monitor: SessionDirectoryMonitor?
    private var refreshTimer: Timer?
    private var petIslandController: PetIslandController?
    private lazy var dismissalCoordinator = PopoverDismissalCoordinator(
        eventSource: outsideClickEventSource,
        closePopover: { [weak self] in self?.popover.performClose(nil) }
    )

    init(
        store: DashboardStore,
        sessionsDirectory: URL,
        renderer: StatusItemRenderer = StatusItemRenderer(),
        outsideClickEventSource: any OutsideClickEventSource = GlobalMouseDownEventSource(),
        petIslandPreferences: PetIslandPreferences = PetIslandPreferences()
    ) {
        self.store = store
        self.sessionsDirectory = sessionsDirectory
        self.renderer = renderer
        self.outsideClickEventSource = outsideClickEventSource
        self.petIslandPreferences = petIslandPreferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func start() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 620, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                store: store,
                petIslandPreferences: petIslandPreferences
            )
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Codex Menu Bar")
        }
        petIslandController = PetIslandController(
            store: store,
            preferences: petIslandPreferences,
            screenProvider: { [weak self] in
                self?.statusItem.button?.window?.screen
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
            },
            openDashboard: { [weak self] in self?.showPopover() }
        )
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
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        dismissalCoordinator.start()
        store.refresh()
    }

    func popoverDidClose(_ notification: Notification) {
        dismissalCoordinator.stop()
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

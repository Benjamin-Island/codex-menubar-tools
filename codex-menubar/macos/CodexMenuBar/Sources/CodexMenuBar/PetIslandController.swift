import AppKit
import Combine
import SwiftUI

struct PetIslandPlacement {
    static let panelSize = NSSize(width: 300, height: 98)

    static func frame(on screen: NSScreen) -> NSRect {
        frame(in: screen.frame, size: panelSize)
    }

    static func frame(in screenFrame: NSRect, size: NSSize) -> NSRect {
        NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
final class PetIslandController: NSObject {
    private let panel: NSPanel
    private let store: DashboardStore
    private let preferences: PetIslandPreferences
    private let screenProvider: () -> NSScreen?
    private let openDashboard: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: DashboardStore,
        preferences: PetIslandPreferences,
        screenProvider: @escaping () -> NSScreen?,
        openDashboard: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.screenProvider = screenProvider
        self.openDashboard = openDashboard

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PetIslandPlacement.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        configurePanel()
        observeChanges()
        updatePresentation()
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.setAccessibilityTitle("Codex Pet Island")
    }

    private func observeChanges() {
        preferences.$isEnabled
            .removeDuplicates()
            .sink { [weak self] _ in self?.updatePresentation() }
            .store(in: &cancellables)

        preferences.$selectedPetID
            .removeDuplicates()
            .sink { [weak self] _ in self?.updatePresentation() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenEnvironmentDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenEnvironmentDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func screenEnvironmentDidChange() {
        updatePresentation()
    }

    private func updatePresentation() {
        guard preferences.isEnabled, let screen = screenProvider() else {
            panel.orderOut(nil)
            return
        }
        rebuildContent(screen: screen)
        // Installing an NSHostingController can update a borderless panel's
        // content size. Apply the final screen-space frame afterwards so the
        // panel remains attached to the display's top edge.
        panel.setFrame(PetIslandPlacement.frame(on: screen), display: true)
        panel.orderFrontRegardless()
    }

    private func rebuildContent(screen: NSScreen? = nil) {
        let display = screen ?? screenProvider()
        let rootView = PetIslandView(
            store: store,
            preferences: preferences,
            isNotchedDisplay: (display?.safeAreaInsets.top ?? 0) > 0,
            openDashboard: openDashboard
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
    }
}

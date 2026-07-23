import AppKit
import Combine
import SwiftUI

enum PetSurfaceMode: Equatable {
    case notch
    case floating
}

struct PetIslandPlacement {
    static let notchWidth: CGFloat = 236
    static let floatingSize = NSSize(width: 68, height: 72)
    static let expandedSize = NSSize(width: 390, height: 184)

    static func mode(on screen: NSScreen) -> PetSurfaceMode {
        let hasAuxiliaryAreas: Bool
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hasAuxiliaryAreas = !left.isEmpty && !right.isEmpty
        } else {
            hasAuxiliaryAreas = false
        }
        return screen.safeAreaInsets.top > 0 && hasAuxiliaryAreas ? .notch : .floating
    }

    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        max(28, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    static func size(
        mode: PetSurfaceMode,
        expanded: Bool,
        menuBarHeight: CGFloat
    ) -> NSSize {
        if expanded {
            return expandedSize
        }
        switch mode {
        case .notch:
            return NSSize(width: notchWidth, height: menuBarHeight)
        case .floating:
            return floatingSize
        }
    }

    static func frame(
        mode: PetSurfaceMode,
        expanded: Bool,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        menuBarHeight: CGFloat
    ) -> NSRect {
        let size = size(
            mode: mode,
            expanded: expanded,
            menuBarHeight: menuBarHeight
        )
        switch mode {
        case .notch:
            return NSRect(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        case .floating:
            let inset: CGFloat = 14
            return NSRect(
                x: visibleFrame.maxX - size.width - inset,
                y: visibleFrame.maxY - size.height - 10,
                width: size.width,
                height: size.height
            )
        }
    }
}

@MainActor
final class PetIslandController: NSObject {
    private let panel: NSPanel
    private let store: DashboardStore
    private let preferences: PetIslandPreferences
    private let screenProvider: () -> NSScreen?
    private let openDashboard: () -> Void
    private var isExpanded = false
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
            contentRect: NSRect(origin: .zero, size: PetIslandPlacement.floatingSize),
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
        panel.setAccessibilityTitle("Codex Pet Status")
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

        preferences.$presentationMode
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.isExpanded = false
                self?.updatePresentation()
            }
            .store(in: &cancellables)

        store.$snapshot
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
        isExpanded = false
        updatePresentation()
    }

    private func toggleExpanded() {
        isExpanded.toggle()
        updatePresentation()
    }

    private func updatePresentation() {
        guard preferences.isEnabled, let screen = screenProvider() else {
            panel.orderOut(nil)
            return
        }
        let mode = resolvedMode(on: screen)
        let menuBarHeight = PetIslandPlacement.menuBarHeight(on: screen)
        rebuildContent(screen: screen, mode: mode, menuBarHeight: menuBarHeight)
        panel.setFrame(
            PetIslandPlacement.frame(
                mode: mode,
                expanded: isExpanded,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                menuBarHeight: menuBarHeight
            ),
            display: true,
            animate: panel.isVisible
        )
        panel.orderFrontRegardless()
    }

    private func rebuildContent(
        screen: NSScreen? = nil,
        mode requestedMode: PetSurfaceMode? = nil,
        menuBarHeight requestedMenuBarHeight: CGFloat? = nil
    ) {
        guard let display = screen ?? screenProvider() else { return }
        let mode = requestedMode ?? resolvedMode(on: display)
        let menuBarHeight = requestedMenuBarHeight
            ?? PetIslandPlacement.menuBarHeight(on: display)
        let rootView = PetIslandView(
            store: store,
            preferences: preferences,
            mode: mode,
            isExpanded: isExpanded,
            menuBarHeight: menuBarHeight,
            toggleExpanded: { [weak self] in self?.toggleExpanded() },
            openDashboard: { [weak self] in
                self?.isExpanded = false
                self?.updatePresentation()
                self?.openDashboard()
            }
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
    }

    private func resolvedMode(on screen: NSScreen) -> PetSurfaceMode {
        switch preferences.presentationMode {
        case .automatic:
            PetIslandPlacement.mode(on: screen)
        case .notch:
            .notch
        case .floating:
            .floating
        }
    }
}

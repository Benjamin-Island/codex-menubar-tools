import AppKit
import Combine
import SwiftUI

enum PetSurfaceMode: Equatable {
    case notch
    case floating
}

enum PetDockEdge: Equatable {
    case left
    case right
}

struct PetIslandPlacement {
    static let notchWidth: CGFloat = 236
    static let floatingSize = NSSize(width: 324, height: 132)
    static let expandedSize = NSSize(width: 410, height: 380)
    static let peekSize = NSSize(width: 92, height: 96)

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
        menuBarHeight: CGFloat,
        peeking: Bool = false
    ) -> NSSize {
        if mode == .floating, peeking {
            return peekSize
        }
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
    private var isPeeking = false
    private var dockEdge: PetDockEdge?
    private var movementDirection: PetDockEdge = .right
    private var floatingOrigin: NSPoint?
    private var floatingScreenNumber: NSNumber?
    private var dragStartFrame: NSRect?
    private var isDragging = false
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
        if isPeeking {
            isPeeking = false
            updatePresentation(animateFrame: false)
            return
        }
        isExpanded.toggle()
        updatePresentation()
    }

    private func updatePresentation(animateFrame: Bool = true) {
        guard preferences.isEnabled, let screen = preferredScreen() else {
            panel.orderOut(nil)
            return
        }
        let mode = resolvedMode(on: screen)
        if mode == .notch {
            isPeeking = false
            dockEdge = nil
            floatingOrigin = nil
            floatingScreenNumber = nil
        }
        let menuBarHeight = PetIslandPlacement.menuBarHeight(on: screen)
        let targetFrame: NSRect?
        if !isDragging {
            let frame = presentationFrame(
                mode: mode,
                screen: screen,
                menuBarHeight: menuBarHeight
            )
            targetFrame = frame
            panel.setFrame(
                frame,
                display: true,
                animate: animateFrame && panel.isVisible
            )
        } else {
            targetFrame = nil
        }
        rebuildContent(screen: screen, mode: mode, menuBarHeight: menuBarHeight)
        if let targetFrame {
            panel.setFrame(targetFrame, display: true, animate: false)
        }
        panel.orderFrontRegardless()
    }

    private func presentationFrame(
        mode: PetSurfaceMode,
        screen: NSScreen,
        menuBarHeight: CGFloat
    ) -> NSRect {
        guard mode == .floating else {
            return PetIslandPlacement.frame(
                mode: mode,
                expanded: isExpanded,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                menuBarHeight: menuBarHeight
            )
        }

        if isPeeking, let dockEdge {
            let size = PetIslandPlacement.peekSize
            let preferredY = floatingOrigin?.y
                ?? screen.visibleFrame.maxY - size.height - 10
            let y = min(
                screen.visibleFrame.maxY - size.height,
                max(screen.visibleFrame.minY, preferredY)
            )
            let x = dockEdge == .left
                ? screen.visibleFrame.minX
                : screen.visibleFrame.maxX - size.width
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        let size = PetIslandPlacement.size(
            mode: mode,
            expanded: isExpanded,
            menuBarHeight: menuBarHeight
        )
        guard let origin = floatingOrigin else {
            return PetIslandPlacement.frame(
                mode: mode,
                expanded: isExpanded,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                menuBarHeight: menuBarHeight
            )
        }
        return clampedFrame(
            NSRect(origin: origin, size: size),
            to: screen.visibleFrame
        )
    }

    private func clampedFrame(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        result.origin.x = min(
            visibleFrame.maxX - frame.width,
            max(visibleFrame.minX, result.origin.x)
        )
        result.origin.y = min(
            visibleFrame.maxY - frame.height,
            max(visibleFrame.minY, result.origin.y)
        )
        return result
    }

    private func beginFloatingDrag() {
        guard !isExpanded, !isPeeking else { return }
        dragStartFrame = panel.frame
        isDragging = true
        dockEdge = nil
    }

    private func updateFloatingDrag(_ translation: CGSize) {
        guard isDragging, let dragStartFrame else { return }
        var frame = dragStartFrame
        frame.origin.x += translation.width
        frame.origin.y -= translation.height
        panel.setFrameOrigin(frame.origin)
    }

    private func endFloatingDrag(_ translation: CGSize) {
        guard isDragging else { return }
        updateFloatingDrag(translation)
        isDragging = false
        dragStartFrame = nil

        let screen = screenForPanel()
        floatingScreenNumber = screenNumber(for: screen)
        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        let snapDistance: CGFloat = 44
        if frame.minX <= visibleFrame.minX + snapDistance {
            dockEdge = .left
            isPeeking = true
        } else if frame.maxX >= visibleFrame.maxX - snapDistance {
            dockEdge = .right
            isPeeking = true
        } else {
            dockEdge = nil
            isPeeking = false
        }
        floatingOrigin = clampedFrame(frame, to: visibleFrame).origin
        updatePresentation(animateFrame: false)
    }

    private func screenForPanel() -> NSScreen {
        NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        })
            ?? NSScreen.screens.max(by: {
                intersectionArea($0.frame, panel.frame)
                    < intersectionArea($1.frame, panel.frame)
            })
            ?? panel.screen
            ?? screenProvider()
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func intersectionArea(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.width * intersection.height
    }

    private func preferredScreen() -> NSScreen? {
        if let floatingScreenNumber,
           let screen = NSScreen.screens.first(where: {
               screenNumber(for: $0) == floatingScreenNumber
           }) {
            return screen
        }
        floatingScreenNumber = nil
        return screenProvider() ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func screenNumber(for screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
    }

    private func rebuildContent(
        screen: NSScreen? = nil,
        mode requestedMode: PetSurfaceMode? = nil,
        menuBarHeight requestedMenuBarHeight: CGFloat? = nil
    ) {
        guard let display = screen ?? preferredScreen() else { return }
        let mode = requestedMode ?? resolvedMode(on: display)
        let menuBarHeight = requestedMenuBarHeight
            ?? PetIslandPlacement.menuBarHeight(on: display)
        let rootView = PetIslandView(
            store: store,
            preferences: preferences,
            mode: mode,
            isExpanded: isExpanded,
            isPeeking: isPeeking,
            dockEdge: dockEdge,
            initialDirection: movementDirection,
            menuBarHeight: menuBarHeight,
            toggleExpanded: { [weak self] in self?.toggleExpanded() },
            beginDrag: { [weak self] in self?.beginFloatingDrag() },
            changeDirection: { [weak self] direction in
                self?.movementDirection = direction
            },
            updateDrag: { [weak self] translation in
                self?.updateFloatingDrag(translation)
            },
            endDrag: { [weak self] translation in
                self?.endFloatingDrag(translation)
            },
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

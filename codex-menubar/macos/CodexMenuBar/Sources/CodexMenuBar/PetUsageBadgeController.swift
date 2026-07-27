import AppKit
import Combine
import CoreGraphics
import SwiftUI

struct PetUsageScreenDescriptor: Equatable {
    let quartzFrame: CGRect
    let appKitFrame: CGRect
    let visibleFrame: CGRect

    static func currentScreens() -> [PetUsageScreenDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                return nil
            }
            return PetUsageScreenDescriptor(
                quartzFrame: CGDisplayBounds(
                    CGDirectDisplayID(number.uint32Value)
                ),
                appKitFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }
}

@MainActor
protocol PetUsagePanel: AnyObject {
    var contentViewController: NSViewController? { get set }
    var onEscape: (() -> Void)? { get set }
    var frame: CGRect { get }
    var isVisible: Bool { get }

    func setFrame(_ frame: CGRect, display: Bool)
    func show(makeKey: Bool)
    func hide()
}

@MainActor
class PetUsagePanelWindow: NSPanel, PetUsagePanel {
    var onEscape: (() -> Void)?

    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }

    func show(makeKey: Bool) {
        orderFrontRegardless()
        if makeKey {
            self.makeKey()
        }
    }

    func hide() {
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
final class PetUsageSummaryPanel: PetUsagePanelWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PetUsageBadgeController {
    private struct Geometry {
        let anchorFrame: CGRect
        let obstacleFrames: [CGRect]
        let visibleFrame: CGRect
        let badgeFrame: CGRect
    }

    private let store: DashboardStore
    private let permissionController: PetUsageBadgePermissionController
    private let languagePreferences: AppLanguagePreferences
    private let tracker: any PetUsageBadgeTracking
    private let outsideClickEventSource: any OutsideClickEventSource
    private let screenDescriptors: () -> [PetUsageScreenDescriptor]
    private let badgePanel: any PetUsagePanel
    private let summaryPanel: any PetUsagePanel
    private var cancellables: Set<AnyCancellable> = []
    private var visibility: PetUsageBadgeVisibility = .hidden
    private var geometry: Geometry?
    private var summaryFrame: CGRect?
    private var isStarted = false

    init(
        store: DashboardStore,
        permissionController: PetUsageBadgePermissionController,
        languagePreferences: AppLanguagePreferences,
        tracker: any PetUsageBadgeTracking,
        outsideClickEventSource: any OutsideClickEventSource =
            GlobalMouseDownEventSource(),
        screenDescriptors: @escaping () -> [PetUsageScreenDescriptor] = {
            PetUsageScreenDescriptor.currentScreens()
        },
        badgePanel: (any PetUsagePanel)? = nil,
        summaryPanel: (any PetUsagePanel)? = nil
    ) {
        self.store = store
        self.permissionController = permissionController
        self.languagePreferences = languagePreferences
        self.tracker = tracker
        self.outsideClickEventSource = outsideClickEventSource
        self.screenDescriptors = screenDescriptors
        self.badgePanel = badgePanel
            ?? PetUsagePanelWindow(size: PetUsageBadgePlacement.badgeSize)
        self.summaryPanel = summaryPanel
            ?? PetUsageSummaryPanel(size: PetUsageBadgePlacement.summarySize)

        self.summaryPanel.onEscape = { [weak self] in
            self?.dismissSummary(event: .escapePressed)
        }
        updateHostedViews()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        tracker.onUpdate = { [weak self] update in
            self?.handle(update)
        }
        permissionController.$isEnabled
            .combineLatest(permissionController.$status)
            .map { isEnabled, status in
                isEnabled && status == .authorized
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] canTrack in
                self?.trackingEligibilityDidChange(canTrack)
            }
            .store(in: &cancellables)
        languagePreferences.$selection
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateHostedViews()
            }
            .store(in: &cancellables)

        if permissionController.canTrack {
            tracker.start()
        } else {
            apply(event: .disabled)
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        tracker.onUpdate = nil
        tracker.stop()
        geometry = nil
        summaryFrame = nil
        visibility = .hidden
        render()
    }

    func toggleSummary() {
        guard isStarted, permissionController.canTrack else { return }
        if visibility == .summary {
            apply(event: .badgeClicked(summaryCanFit: true))
            return
        }
        guard visibility == .badge, let geometry else { return }
        let candidate = PetUsageBadgePlacement.summaryFrame(
            badgeFrame: geometry.badgeFrame,
            anchorFrame: geometry.anchorFrame,
            obstacleFrames: geometry.obstacleFrames,
            visibleFrame: geometry.visibleFrame
        )
        summaryFrame = candidate
        apply(event: .badgeClicked(summaryCanFit: candidate != nil))
    }

    private func trackingEligibilityDidChange(_ canTrack: Bool) {
        if canTrack {
            tracker.start()
        } else {
            tracker.stop()
            geometry = nil
            summaryFrame = nil
            apply(event: .disabled)
        }
    }

    private func handle(_ update: PetUsageBadgeTrackingUpdate) {
        guard isStarted, permissionController.canTrack else { return }
        guard let observation = update.observation else {
            geometry = nil
            summaryFrame = nil
            apply(event: .anchorLost)
            return
        }
        guard
            let screen = screenDescriptors().first(where: {
                $0.quartzFrame.contains(
                    CGPoint(
                        x: observation.anchorFrame.midX,
                        y: observation.anchorFrame.midY
                    )
                )
            })
        else {
            geometry = nil
            summaryFrame = nil
            apply(event: .anchorLost)
            return
        }

        let anchorFrame = PetUsageBadgePlacement.appKitFrame(
            from: observation.anchorFrame,
            quartzScreenFrame: screen.quartzFrame,
            appKitScreenFrame: screen.appKitFrame
        )
        let obstacleFrames = observation.obstacleFrames.map {
            PetUsageBadgePlacement.appKitFrame(
                from: $0,
                quartzScreenFrame: screen.quartzFrame,
                appKitScreenFrame: screen.appKitFrame
            )
        }
        let previousBadgeFrame = geometry?.badgeFrame
        guard
            let badgeFrame = PetUsageBadgePlacement.badgeFrame(
                anchorFrame: anchorFrame,
                obstacleFrames: obstacleFrames,
                visibleFrame: screen.visibleFrame,
                previousFrame: previousBadgeFrame
            )
        else {
            geometry = nil
            summaryFrame = nil
            apply(event: .anchorLost)
            return
        }

        if update.isMoving {
            apply(event: .movementStarted)
        }
        geometry = Geometry(
            anchorFrame: anchorFrame,
            obstacleFrames: obstacleFrames,
            visibleFrame: screen.visibleFrame,
            badgeFrame: badgeFrame
        )
        badgePanel.setFrame(badgeFrame, display: true)
        if visibility == .summary {
            summaryFrame = PetUsageBadgePlacement.summaryFrame(
                badgeFrame: badgeFrame,
                anchorFrame: anchorFrame,
                obstacleFrames: obstacleFrames,
                visibleFrame: screen.visibleFrame
            )
            if summaryFrame == nil {
                visibility = .badge
            }
        }
        apply(event: .anchorFound)
    }

    private func dismissSummary(event: PetUsageBadgeEvent) {
        guard visibility == .summary else { return }
        apply(event: event)
    }

    private func apply(event: PetUsageBadgeEvent) {
        visibility = PetUsageBadgeState.reduce(visibility, event: event)
        render()
    }

    private func render() {
        switch visibility {
        case .hidden:
            outsideClickEventSource.stop()
            summaryPanel.hide()
            badgePanel.hide()
        case .badge:
            outsideClickEventSource.stop()
            summaryPanel.hide()
            badgePanel.show(makeKey: false)
        case .summary:
            guard let summaryFrame else {
                visibility = .badge
                render()
                return
            }
            summaryPanel.setFrame(summaryFrame, display: true)
            badgePanel.show(makeKey: false)
            summaryPanel.show(makeKey: true)
            outsideClickEventSource.start { [weak self] in
                self?.dismissSummary(event: .outsideClicked)
            }
        }
    }

    private func updateHostedViews() {
        let language = languagePreferences.resolvedLanguage
        badgePanel.contentViewController = NSHostingController(
            rootView: PetUsageBadgeView(
                store: store,
                language: language,
                onClick: { [weak self] in self?.toggleSummary() }
            )
        )
        summaryPanel.contentViewController = NSHostingController(
            rootView: PetUsageSummaryView(
                store: store,
                language: language
            )
        )
    }
}

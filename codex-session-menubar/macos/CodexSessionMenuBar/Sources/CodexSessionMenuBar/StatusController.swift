import AppKit
import CodexSessionCore
import Foundation

@MainActor
final class StatusController: NSObject {
    private let statusItem: NSStatusItem
    private let inventory: SessionInventory
    private let sessionsDirectory: URL
    private let refreshInterval: TimeInterval
    private var menuBuilder: SessionMenuBuilder!
    private var timer: Timer?
    private var sessionMonitor: SessionDirectoryMonitor?
    private var lastResult: SessionInventoryResult?
    private var isRefreshing = false
    private var needsRefresh = false

    init(
        inventory: SessionInventory,
        sessionsDirectory: URL,
        refreshInterval: TimeInterval = 5
    ) {
        self.inventory = inventory
        self.sessionsDirectory = sessionsDirectory
        self.refreshInterval = refreshInterval
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menuBuilder = SessionMenuBuilder(
            target: self,
            refreshAction: #selector(refreshFromMenu),
            quitAction: #selector(quit)
        )
    }

    func start() {
        updateStatusItem(countLabel: "…", color: .secondaryLabelColor, isError: false)
        rebuildMenu()
        ensureSessionMonitorStarted()
        refresh()

        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh() {
        guard !isRefreshing else {
            needsRefresh = true
            return
        }
        isRefreshing = true
        needsRefresh = false

        let inventory = inventory
        DispatchQueue.global(qos: .utility).async {
            let result = inventory.read()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isRefreshing = false
                ensureSessionMonitorStarted()
                apply(result)
                if needsRefresh {
                    refresh()
                }
            }
        }
    }

    private func ensureSessionMonitorStarted() {
        guard sessionMonitor == nil else { return }
        let monitor = SessionDirectoryMonitor(directory: sessionsDirectory) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        guard monitor.start() else { return }
        sessionMonitor = monitor
    }

    private func apply(_ result: SessionInventoryResult) {
        lastResult = result
        switch result {
        case let .snapshots(snapshots):
            let color: NSColor
            if snapshots.contains(where: { $0.activity == .running }) {
                color = .systemGreen
            } else if snapshots.isEmpty {
                color = .secondaryLabelColor
            } else {
                color = .systemYellow
            }
            updateStatusItem(
                countLabel: String(snapshots.count),
                color: color,
                isError: false
            )
        case .failure:
            updateStatusItem(countLabel: "!", color: .systemRed, isError: true)
        }
        rebuildMenu()
    }

    private func updateStatusItem(
        countLabel: String,
        color: NSColor,
        isError: Bool
    ) {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        let image = NSImage(
            systemSymbolName: "terminal.fill",
            accessibilityDescription: "Codex CLI sessions"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = false

        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " \(countLabel)"
        statusItem.button?.toolTip = isError
            ? "Codex CLI session status unavailable"
            : "\(countLabel) interactive Codex TUI sessions"
        statusItem.button?.setAccessibilityLabel("Codex CLI sessions")
        statusItem.button?.setAccessibilityValue(countLabel)
    }

    private func rebuildMenu() {
        statusItem.menu = menuBuilder.makeMenu(result: lastResult)
    }
}

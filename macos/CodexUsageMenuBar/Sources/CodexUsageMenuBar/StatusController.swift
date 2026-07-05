import AppKit
import CodexUsageCore
import Foundation

@MainActor
final class StatusController: NSObject {
    private let statusItem: NSStatusItem
    private let sessionsDirectory: URL
    private let makeReader: @Sendable () -> CodexLogReader
    private let renderer: UsageIndicatorRenderer
    private let refreshInterval: TimeInterval
    private var timer: Timer?
    private var lastResult: UsageReadResult?

    init(
        sessionsDirectory: URL,
        makeReader: @escaping @Sendable () -> CodexLogReader,
        renderer: UsageIndicatorRenderer = UsageIndicatorRenderer(),
        refreshInterval: TimeInterval
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.makeReader = makeReader
        self.renderer = renderer
        self.refreshInterval = refreshInterval
        self.statusItem = NSStatusBar.system.statusItem(withLength: UsageIndicatorRenderer.imageSize.width)
        super.init()
    }

    func start() {
        configureMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh() {
        let sessionsDirectory = sessionsDirectory
        let makeReader = makeReader
        DispatchQueue.global(qos: .utility).async {
            let reader = makeReader()
            let result = reader.readLatestSnapshot(sessionsDirectory: sessionsDirectory)
            DispatchQueue.main.async { [weak self] in
                self?.apply(result)
            }
        }
    }

    private func apply(_ result: UsageReadResult) {
        lastResult = result

        let remainingPercent: Int?
        let label: String
        switch result {
        case .snapshot(let snapshot):
            remainingPercent = snapshot.primary?.remainingPercent
            label = UsageFormatting.menuLabel(remainingPercent)
        case .failure(let error):
            remainingPercent = nil
            label = error.menuValue
        }

        statusItem.button?.image = renderer.image(
            label: label,
            progress: remainingPercent.map { Double($0) / 100.0 }
        )
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = label == "--" || label == "!"
            ? "Codex usage unavailable"
            : "Codex usage \(label)% remaining"
        configureMenu()
    }

    private func configureMenu() {
        let menu = NSMenu()

        switch lastResult {
        case .snapshot(let snapshot):
            menu.addItem(NSMenuItem(title: "Codex usage", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
            addWindowItems(to: menu, prefix: "Primary", window: snapshot.primary)
            addWindowItems(to: menu, prefix: "Secondary", window: snapshot.secondary)
            menu.addItem(NSMenuItem(title: "Plan: \(snapshot.planType ?? "--")", action: nil, keyEquivalent: ""))
            if let credits = snapshot.creditsDescription {
                menu.addItem(NSMenuItem(title: "Credits: \(credits)", action: nil, keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(
                title: "Last reported: \(UsageFormatting.dateLabel(snapshot.reportedAt))",
                action: nil,
                keyEquivalent: ""
            ))
            menu.addItem(NSMenuItem(title: "Source: local Codex session logs", action: nil, keyEquivalent: ""))

        case .failure(let error):
            menu.addItem(NSMenuItem(title: error.message, action: nil, keyEquivalent: ""))
            if let detail = error.detail {
                menu.addItem(NSMenuItem(title: "Detail: \(detail)", action: nil, keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(title: "Source: local Codex session logs", action: nil, keyEquivalent: ""))

        case nil:
            menu.addItem(NSMenuItem(title: "Loading Codex usage", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func addWindowItems(to menu: NSMenu, prefix: String, window: WindowUsage?) {
        guard let window else {
            menu.addItem(NSMenuItem(title: "\(prefix) remaining: --", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "\(prefix) resets: --", action: nil, keyEquivalent: ""))
            return
        }

        menu.addItem(NSMenuItem(
            title: "\(window.label) remaining: \(UsageFormatting.percentLabel(window.remainingPercent))",
            action: nil,
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "\(window.label) resets: \(UsageFormatting.dateLabel(window.resetsAt))",
            action: nil,
            keyEquivalent: ""
        ))
    }
}

import AppKit
import CodexSessionCore

@MainActor
final class SessionMenuBuilder {
    private weak var target: AnyObject?
    private let refreshAction: Selector
    private let quitAction: Selector

    init(target: AnyObject, refreshAction: Selector, quitAction: Selector) {
        self.target = target
        self.refreshAction = refreshAction
        self.quitAction = quitAction
    }

    func makeMenu(result: SessionInventoryResult?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(informationalItem(title: "Codex CLI Sessions"))

        switch result {
        case let .snapshots(snapshots):
            addSnapshots(snapshots, to: menu)
        case let .failure(error):
            menu.addItem(informationalItem(title: error.message, toolTip: error.detail))
            if let detail = error.detail {
                menu.addItem(informationalItem(title: "Detail: \(detail)", toolTip: detail))
            }
        case nil:
            menu.addItem(informationalItem(title: "Loading interactive Codex TUI sessions"))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(
            title: "Refresh",
            action: refreshAction,
            keyEquivalent: "r"
        ))
        menu.addItem(actionItem(
            title: "Quit",
            action: quitAction,
            keyEquivalent: "q"
        ))
        return menu
    }

    private func addSnapshots(_ snapshots: [SessionDisplaySnapshot], to menu: NSMenu) {
        guard !snapshots.isEmpty else {
            menu.addItem(informationalItem(title: "No interactive Codex TUI sessions"))
            return
        }

        let noun = snapshots.count == 1 ? "session" : "sessions"
        menu.addItem(informationalItem(
            title: "\(snapshots.count) interactive TUI \(noun)"
        ))
        menu.addItem(.separator())

        for snapshot in snapshots {
            let stateLabel = snapshot.activity == .running ? "运行中" : "停滞"
            let stateItem = informationalItem(
                title: "\(stateLabel) — \(snapshot.displayTaskDescription)",
                toolTip: snapshot.taskDescription
            )
            stateItem.image = stateImage(for: snapshot.activity)
            menu.addItem(stateItem)
            menu.addItem(informationalItem(
                title: snapshot.workingDirectory,
                toolTip: snapshot.workingDirectory,
                indentationLevel: 1
            ))
        }
    }

    private func informationalItem(
        title: String,
        toolTip: String? = nil,
        indentationLevel: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.target = nil
        item.toolTip = toolTip
        item.indentationLevel = indentationLevel
        return item
    }

    private func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    private func stateImage(for activity: SessionActivity) -> NSImage? {
        let color: NSColor = activity == .running ? .systemGreen : .systemYellow
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        let image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: activity == .running ? "运行中" : "停滞"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }
}

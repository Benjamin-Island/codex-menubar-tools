import AppKit
import CodexMenuBarCore
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let sessionsDirectory = environment["CODEX_SESSIONS_DIR"].map(URL.init(fileURLWithPath:))
            ?? codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        let sessionIndexURL = environment["CODEX_SESSION_INDEX"].map(URL.init(fileURLWithPath:))
            ?? codexDirectory.appendingPathComponent("session_index.jsonl")

        let reader = DashboardReader(
            logIndex: IncrementalCodexLogIndex(),
            historyAggregator: TokenHistoryAggregator(),
            rateLimitReducer: RateLimitReducer(),
            sessionInventory: SessionInventory(
                processProvider: DarwinProcessProvider(sessionsDirectory: sessionsDirectory),
                classifier: InteractiveTUIClassifier(),
                currentUID: getuid()
            ),
            sessionsDirectory: sessionsDirectory,
            sessionIndexURL: sessionIndexURL
        )
        let store = DashboardStore(
            snapshot: .loading(at: Date()),
            reader: {
                await Task.detached(priority: .utility) { reader.read() }.value
            }
        )
        let controller = StatusController(store: store, sessionsDirectory: sessionsDirectory)
        controller.start()
        statusController = controller
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

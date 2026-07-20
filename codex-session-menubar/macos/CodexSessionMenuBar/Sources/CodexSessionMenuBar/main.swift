import AppKit
import CodexSessionCore
import Darwin
import Foundation

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let codexDirectory = Self.codexDirectory()
        let sessionsDirectory = Self.sessionsDirectory(in: codexDirectory)
        let sessionIndexURL = Self.sessionIndexURL(in: codexDirectory)
        let inventory = SessionInventory(
            processProvider: DarwinProcessProvider(sessionsDirectory: sessionsDirectory),
            classifier: InteractiveTUIClassifier(),
            logReader: CodexSessionLogReader(),
            sessionsDirectory: sessionsDirectory,
            sessionIndexURL: sessionIndexURL,
            currentUID: getuid()
        )
        statusController = StatusController(
            inventory: inventory,
            sessionsDirectory: sessionsDirectory,
            refreshInterval: 5
        )
        statusController?.start()
    }

    private static func codexDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func sessionsDirectory(in codexDirectory: URL) -> URL {
        environmentURL(named: "CODEX_SESSIONS_DIR")
            ?? codexDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    private static func sessionIndexURL(in codexDirectory: URL) -> URL {
        environmentURL(named: "CODEX_SESSION_INDEX")
            ?? codexDirectory.appendingPathComponent("session_index.jsonl")
    }

    private static func environmentURL(named name: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
    }
}

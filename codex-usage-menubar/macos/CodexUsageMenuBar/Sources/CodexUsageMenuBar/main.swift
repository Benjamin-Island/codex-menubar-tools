import AppKit
import CodexUsageCore
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
        let sessionsDirectory = Self.sessionsDirectory()
        statusController = StatusController(
            sessionsDirectory: sessionsDirectory,
            makeReader: { CodexLogReader() },
            refreshInterval: 5
        )
        statusController?.start()
    }

    private static func sessionsDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_SESSIONS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions")
    }
}

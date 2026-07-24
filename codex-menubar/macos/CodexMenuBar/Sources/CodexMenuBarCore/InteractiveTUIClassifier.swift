import Foundation

public struct InteractiveTUIClassifier: Sendable {
    private static let allowedSubcommands: Set<String> = ["resume", "fork"]
    private static let nonInteractiveSubcommands: Set<String> = [
        "exec", "review", "login", "logout", "mcp", "plugin", "mcp-server",
        "app-server", "remote-control", "app", "completion", "update", "doctor",
        "sandbox", "debug", "apply", "archive", "delete", "unarchive", "cloud",
        "exec-server", "features", "help"
    ]
    private static let optionsWithValue: Set<String> = [
        "-c", "--config", "--enable", "--disable", "--remote",
        "--remote-auth-token-env", "-i", "--image", "-m", "--model",
        "--local-provider", "-p", "--profile", "-s", "--sandbox", "-C", "--cd",
        "--add-dir", "-a", "--ask-for-approval"
    ]
    private static let excludedPathMarkers = [
        "/chatgpt.app/", "/.vscode/extensions/", "/.openclaw/"
    ]

    public init() {}

    public func candidates(
        from processes: [ProcessSnapshot],
        currentUID: UInt32
    ) -> [ProcessSnapshot] {
        processes.filter { process in
            guard process.userID == currentUID,
                  URL(fileURLWithPath: process.executablePath).lastPathComponent == "codex"
            else {
                return false
            }
            if isDesktopAppServer(process) { return true }
            guard process.hasControllingTerminal else { return false }
            let normalizedPath = process.executablePath.lowercased()
            guard !Self.excludedPathMarkers.contains(where: normalizedPath.contains) else {
                return false
            }
            guard let subcommand = subcommand(in: process.arguments) else { return true }
            return Self.allowedSubcommands.contains(subcommand)
        }.sorted { $0.pid < $1.pid }
    }

    func isDesktopAppServer(_ process: ProcessSnapshot) -> Bool {
        process.executablePath.lowercased().contains("/chatgpt.app/")
            && subcommand(in: process.arguments) == "app-server"
    }

    private func subcommand(in arguments: [String]) -> String? {
        var tokens = arguments
        if let first = tokens.first,
           URL(fileURLWithPath: first).lastPathComponent == "codex" {
            tokens.removeFirst()
        }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "--" { return nil }
            if token.hasPrefix("-") {
                if token.contains("=") {
                    index += 1
                } else if Self.optionsWithValue.contains(token) {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if Self.allowedSubcommands.contains(token) || Self.nonInteractiveSubcommands.contains(token) {
                return token
            }
            return nil
        }
        return nil
    }
}

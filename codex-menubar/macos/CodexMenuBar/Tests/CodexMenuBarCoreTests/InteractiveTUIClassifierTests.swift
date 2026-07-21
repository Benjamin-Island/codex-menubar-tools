import Foundation
import XCTest
@testable import CodexMenuBarCore

final class InteractiveTUIClassifierTests: XCTestCase {
    private let classifier = InteractiveTUIClassifier()
    private let currentUID: UInt32 = 501

    func testAcceptsPlainResumeForkAndPromptTUIs() {
        let processes = [
            process(pid: 1, arguments: ["codex"]),
            process(pid: 2, arguments: ["codex", "resume", "--last"]),
            process(pid: 3, arguments: ["codex", "fork", "--last"]),
            process(pid: 4, arguments: ["codex", "--model", "gpt-5.5", "--search", "fix tests"])
        ]
        XCTAssertEqual(classifier.candidates(from: processes, currentUID: currentUID).map(\.pid), [1, 2, 3, 4])
    }

    func testRejectsDocumentedNonInteractiveSubcommands() {
        let commands = [
            "exec", "review", "login", "logout", "mcp", "plugin", "mcp-server",
            "app-server", "remote-control", "app", "completion", "update", "doctor",
            "sandbox", "debug", "apply", "archive", "delete", "unarchive", "cloud",
            "exec-server", "features", "help"
        ]
        for command in commands {
            XCTAssertTrue(
                classifier.candidates(from: [process(arguments: ["codex", command])], currentUID: currentUID).isEmpty,
                "Expected \(command) to be rejected"
            )
        }
    }

    func testRejectsWrongUserNoTerminalNonCodexAndEmbeddedExecutables() {
        let rejected = [
            process(pid: 1, userID: 999),
            process(pid: 2, hasControllingTerminal: false),
            process(pid: 3, executablePath: "/usr/bin/bash", arguments: ["bash"]),
            process(pid: 4, executablePath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            process(pid: 5, executablePath: "/Users/me/.vscode/extensions/openai.chatgpt/bin/codex"),
            process(pid: 6, executablePath: "/Users/me/.openclaw/projects/vendor/codex")
        ]
        XCTAssertTrue(classifier.candidates(from: rejected, currentUID: currentUID).isEmpty)
    }

    func testReturnsNativeChildWithoutNodeWrapperDuplicate() {
        let wrapper = process(
            pid: 10,
            executablePath: "/opt/homebrew/bin/node",
            arguments: ["node", "/opt/homebrew/bin/codex"]
        )
        let native = process(pid: 11, parentPID: 10)
        XCTAssertEqual(classifier.candidates(from: [wrapper, native], currentUID: currentUID).map(\.pid), [11])
    }

    private func process(
        pid: Int32 = 42,
        parentPID: Int32 = 1,
        userID: UInt32 = 501,
        executablePath: String = "/opt/homebrew/lib/node_modules/@openai/codex/vendor/codex",
        arguments: [String] = ["codex"],
        hasControllingTerminal: Bool = true
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            parentPID: parentPID,
            userID: userID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: "/tmp/work",
            hasControllingTerminal: hasControllingTerminal,
            openFilePaths: []
        )
    }
}

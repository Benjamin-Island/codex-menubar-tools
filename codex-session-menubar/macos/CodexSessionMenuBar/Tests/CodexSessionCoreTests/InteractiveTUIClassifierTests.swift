import Foundation
import XCTest
@testable import CodexSessionCore

final class InteractiveTUIClassifierTests: XCTestCase {
    private let classifier = InteractiveTUIClassifier()
    private let currentUID: UInt32 = 501

    func testAcceptsPlainResumeAndForkInteractiveTUIs() {
        let processes = [
            process(pid: 1, arguments: ["codex"]),
            process(pid: 2, arguments: ["codex", "resume", "--last"]),
            process(pid: 3, arguments: ["codex", "fork", "--last"])
        ]

        XCTAssertEqual(classify(processes).map(\.pid), [1, 2, 3])
    }

    func testAcceptsPlainTUIWithGlobalOptionsAndPrompt() {
        let candidate = process(arguments: [
            "codex", "--model", "gpt-5.5", "--search", "fix login tests"
        ])

        XCTAssertEqual(classify([candidate]).map(\.pid), [42])
    }

    func testRejectsEveryDocumentedNonInteractiveSubcommand() {
        let commands = [
            "exec", "review", "login", "logout", "mcp", "plugin", "mcp-server",
            "app-server", "remote-control", "app", "completion", "update", "doctor",
            "sandbox", "debug", "apply", "archive", "delete", "unarchive", "cloud",
            "exec-server", "features", "help"
        ]

        for command in commands {
            let candidate = process(arguments: ["codex", command])
            XCTAssertTrue(classify([candidate]).isEmpty, "Expected \(command) to be rejected")
        }
    }

    func testRejectsProcessWithoutControllingTerminal() {
        XCTAssertTrue(classify([process(hasControllingTerminal: false)]).isEmpty)
    }

    func testRejectsProcessOwnedByAnotherUser() {
        XCTAssertTrue(classify([process(userID: 999)]).isEmpty)
    }

    func testRejectsChatGPTIDEAndOpenClawExecutables() {
        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Users/me/.vscode/extensions/openai.chatgpt/bin/codex",
            "/Users/me/.openclaw/projects/vendor/codex"
        ]

        for (offset, path) in paths.enumerated() {
            XCTAssertTrue(classify([process(pid: Int32(offset + 1), executablePath: path)]).isEmpty)
        }
    }

    func testReturnsNativeChildWithoutNodeWrapperDuplicate() {
        let wrapper = process(
            pid: 10,
            parentPID: 9,
            executablePath: "/opt/homebrew/bin/node",
            arguments: ["node", "/opt/homebrew/bin/codex"]
        )
        let native = process(
            pid: 11,
            parentPID: 10,
            executablePath: "/opt/homebrew/lib/node_modules/@openai/codex/vendor/codex",
            arguments: ["codex"]
        )

        XCTAssertEqual(classify([wrapper, native]).map(\.pid), [11])
    }

    func testRejectsNonCodexNativeExecutable() {
        let process = process(executablePath: "/usr/bin/bash", arguments: ["bash"])

        XCTAssertTrue(classify([process]).isEmpty)
    }

    private func classify(_ processes: [ProcessSnapshot]) -> [ProcessSnapshot] {
        classifier.candidates(from: processes, currentUID: currentUID)
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

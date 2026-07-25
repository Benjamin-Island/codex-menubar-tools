import Foundation
import XCTest
@testable import CodexMenuBar

@MainActor
final class PetConfigurationMonitorTests: XCTestCase {
    func testDeliversChangesToCodexPetConfiguration() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("PetConfigurationMonitorTests-\(UUID().uuidString)")
        let petsRoot = temporary.appendingPathComponent("pets", isDirectory: true)
        let configURL = temporary.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(
            at: petsRoot,
            withIntermediateDirectories: true
        )
        try Data("selected-avatar-id = \"custom:pang-q\"".utf8).write(to: configURL)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let changed = expectation(description: "Pet configuration changed")
        let monitor = PetConfigurationMonitor(
            configURL: configURL,
            petRoots: [petsRoot]
        ) {
            changed.fulfill()
        }
        XCTAssertTrue(monitor.start())

        try await Task.sleep(for: .milliseconds(250))
        try Data(
            "selected-avatar-id = \"custom:sharkler\"".utf8
        ).write(to: configURL)

        await fulfillment(of: [changed], timeout: 3)
        monitor.stop()
    }
}

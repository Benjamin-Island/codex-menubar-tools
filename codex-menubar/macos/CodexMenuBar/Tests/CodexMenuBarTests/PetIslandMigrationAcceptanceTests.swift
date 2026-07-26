import XCTest
import CodexMenuBarCore
@testable import CodexMenuBar

@MainActor
final class PetIslandMigrationAcceptanceTests: XCTestCase {
    func testPetPreferencesDefaultToEnabledAndClampPersistedScale() {
        let suite = "PetIslandMigrationAcceptanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(999.0, forKey: "petIsland.petScalePercent")
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = PetIslandPreferences(
            pets: [],
            defaults: defaults,
            localSelectedPetID: nil
        )

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(preferences.petScalePercent, 300.0)
    }

    func testPetIslandAlwaysPrefersPrimaryUsageWindow() throws {
        let primary = WindowUsage(
            label: "5h",
            usedPercent: 20,
            remainingPercent: 80,
            resetsAt: nil
        )
        let secondary = WindowUsage(
            label: "7d",
            usedPercent: 60,
            remainingPercent: 40,
            resetsAt: nil
        )
        let usage = UsageSnapshot(
            primary: primary,
            secondary: secondary,
            planType: nil,
            creditsDescription: nil,
            reportedAt: nil,
            sourcePath: "/session.jsonl"
        )

        XCTAssertEqual(PetIslandUsageSelection.preferred(from: usage), primary)
    }
}

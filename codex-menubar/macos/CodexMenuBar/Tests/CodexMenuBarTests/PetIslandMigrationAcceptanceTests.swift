import XCTest
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
}

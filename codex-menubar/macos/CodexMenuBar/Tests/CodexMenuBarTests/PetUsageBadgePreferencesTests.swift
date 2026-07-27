import XCTest
@testable import CodexMenuBar

@MainActor
final class PetUsageBadgePreferencesTests: XCTestCase {
    func testFreshInstallEnablesBadgeAndMarksMigrationComplete() {
        let defaults = makeDefaults()

        let preferences = PetUsageBadgePreferences(defaults: defaults)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(
            defaults.object(forKey: PetUsageBadgePreferences.enabledKey) as? Bool,
            true
        )
        XCTAssertTrue(defaults.bool(forKey: PetUsageBadgePreferences.migrationKey))
    }

    func testFirstLaunchCopiesDisabledLegacyStateWithoutDeletingLegacyKey() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "petIsland.enabled")

        let preferences = PetUsageBadgePreferences(defaults: defaults)

        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "petIsland.enabled") as? Bool, false)
    }

    func testFirstLaunchCopiesEnabledLegacyState() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "petIsland.enabled")

        XCTAssertTrue(PetUsageBadgePreferences(defaults: defaults).isEnabled)
    }

    func testMigrationDoesNotOverwriteLaterBadgeChoice() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "petIsland.enabled")
        var preferences: PetUsageBadgePreferences? =
            PetUsageBadgePreferences(defaults: defaults)
        preferences?.isEnabled = false
        preferences = nil
        defaults.set(true, forKey: "petIsland.enabled")

        XCTAssertFalse(PetUsageBadgePreferences(defaults: defaults).isEnabled)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "PetUsageBadgePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

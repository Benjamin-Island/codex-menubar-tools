import Foundation
import XCTest
@testable import CodexMenuBar

@MainActor
final class PetIslandPreferencesTests: XCTestCase {
    func testDefaultPrefersNewestCanonicalLocalPackageAndIgnoresLegacyAutomaticSelection() {
        let suiteName = "PetIslandPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("old-pet", forKey: PetIslandPreferences.selectedPetKey)

        let preferences = PetIslandPreferences(
            pets: [
                pet(id: "old-pet", manifestID: "old-pet", modifiedAt: 1),
                pet(id: "current-backup", manifestID: "current", modifiedAt: 3),
                pet(id: "current", manifestID: "current", modifiedAt: 2)
            ],
            defaults: defaults
        )

        XCTAssertEqual(preferences.selectedPetID, "current")
    }

    func testExplicitSelectionPersistsUntilFollowingLocalConfigurationAgain() {
        let suiteName = "PetIslandPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pets = [
            pet(id: "older", manifestID: "older", modifiedAt: 1),
            pet(id: "newer", manifestID: "newer", modifiedAt: 2)
        ]
        let preferences = PetIslandPreferences(pets: pets, defaults: defaults)

        preferences.selectPet(id: "older")
        let restored = PetIslandPreferences(pets: pets, defaults: defaults)
        XCTAssertEqual(restored.selectedPetID, "older")

        restored.followLocalConfiguration()
        XCTAssertEqual(restored.selectedPetID, "newer")
    }

    func testPresentationModeDefaultsToAutoAndPersistsFloatingChoice() {
        let suiteName = "PetIslandPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = PetIslandPreferences(pets: [], defaults: defaults)
        XCTAssertEqual(preferences.presentationMode, .automatic)

        preferences.presentationMode = .floating
        let restored = PetIslandPreferences(pets: [], defaults: defaults)
        XCTAssertEqual(restored.presentationMode, .floating)
    }

    private func pet(
        id: String,
        manifestID: String?,
        modifiedAt: TimeInterval
    ) -> CodexPet {
        CodexPet(
            id: id,
            manifestID: manifestID,
            displayName: id,
            description: nil,
            spriteVersionNumber: 1,
            spritesheetURL: URL(fileURLWithPath: "/tmp/\(id).webp"),
            manifestModifiedAt: Date(timeIntervalSince1970: modifiedAt)
        )
    }
}

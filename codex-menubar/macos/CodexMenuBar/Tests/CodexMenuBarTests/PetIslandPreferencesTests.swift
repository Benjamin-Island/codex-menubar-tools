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
            defaults: defaults,
            localSelectedPetID: "current"
        )

        XCTAssertEqual(preferences.selectedPetID, "current")
        XCTAssertTrue(preferences.followsLocalPet)
    }

    func testExplicitSelectionPersistsUntilFollowingLocalConfigurationAgain() {
        let suiteName = "PetIslandPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pets = [
            pet(id: "older", manifestID: "older", modifiedAt: 1),
            pet(id: "newer", manifestID: "newer", modifiedAt: 2)
        ]
        let preferences = PetIslandPreferences(
            pets: pets,
            defaults: defaults,
            localSelectedPetID: "newer"
        )

        preferences.selectPet(id: "older")
        XCTAssertFalse(preferences.followsLocalPet)
        let restored = PetIslandPreferences(
            pets: pets,
            defaults: defaults,
            localSelectedPetID: "newer"
        )
        XCTAssertEqual(restored.selectedPetID, "older")
        XCTAssertFalse(restored.followsLocalPet)

        restored.followLocalConfiguration()
        XCTAssertEqual(restored.selectedPetID, "newer")
        XCTAssertTrue(restored.followsLocalPet)
    }

    func testPresentationModeAlwaysUsesAutomaticAndClearsLegacyChoice() {
        let suiteName = "PetIslandPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("floating", forKey: PetIslandPreferences.presentationKey)
        _ = PetIslandPreferences(
            pets: [],
            defaults: defaults,
            localSelectedPetID: nil
        )
        XCTAssertNil(defaults.string(forKey: PetIslandPreferences.presentationKey))
    }

    func testReadsSelectedCustomPetFromLocalCodexConfig() throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pet-config-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: configURL) }
        try Data(
            """
            model = "gpt-5"
            selected-avatar-id = "custom:pang-q"
            """.utf8
        ).write(to: configURL)

        XCTAssertEqual(
            CodexPetSelectionReader(configURL: configURL).selectedPetID(),
            "pang-q"
        )
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

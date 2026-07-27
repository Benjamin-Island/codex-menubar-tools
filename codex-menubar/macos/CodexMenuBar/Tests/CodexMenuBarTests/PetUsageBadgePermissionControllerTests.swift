import XCTest
@testable import CodexMenuBar

@MainActor
final class PetUsageBadgePermissionControllerTests: XCTestCase {
    func testMissingPermissionDisablesPersistedSettingWithoutPromptingAtLaunch() {
        let (preferences, defaults) = makePreferences(enabled: true)
        let provider = FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: false
        )

        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: provider
        )

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.status, .permissionRequired)
        XCTAssertEqual(
            defaults.object(
                forKey: PetUsageBadgePreferences.enabledKey
            ) as? Bool,
            false
        )
        XCTAssertEqual(provider.requestCount, 0)
    }

    func testDeniedPermissionKeepsSettingOffAndPublishesBlockedState() {
        let (preferences, _) = makePreferences(enabled: false)
        let provider = FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: false
        )
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: provider
        )

        controller.setEnabled(true)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.status, .denied)
        XCTAssertEqual(provider.requestCount, 1)
    }

    func testAuthorizedPermissionEnablesSettingWithoutRequestingAgain() {
        let (preferences, _) = makePreferences(enabled: false)
        let provider = FakeScreenCapturePermissionProvider(
            preflightResult: true,
            requestResult: false
        )
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: provider
        )

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.status, .authorized)
        XCTAssertEqual(provider.requestCount, 0)
    }

    func testNewGrantKeepsSettingOnAndRequiresRestart() {
        let (preferences, _) = makePreferences(enabled: false)
        let provider = FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: true
        )
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: provider
        )

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(controller.status, .restartRequired)
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertFalse(controller.canTrack)
    }

    private func makePreferences(
        enabled: Bool
    ) -> (PetUsageBadgePreferences, UserDefaults) {
        let name = "PetUsageBadgePermissionControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: PetUsageBadgePreferences.migrationKey)
        defaults.set(enabled, forKey: PetUsageBadgePreferences.enabledKey)
        return (PetUsageBadgePreferences(defaults: defaults), defaults)
    }
}

@MainActor
private final class FakeScreenCapturePermissionProvider:
    ScreenCapturePermissionProviding
{
    let preflightResult: Bool
    let requestResult: Bool
    private(set) var requestCount = 0

    init(preflightResult: Bool, requestResult: Bool) {
        self.preflightResult = preflightResult
        self.requestResult = requestResult
    }

    func preflight() -> Bool {
        preflightResult
    }

    func request() -> Bool {
        requestCount += 1
        return requestResult
    }
}

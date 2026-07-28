import XCTest
@testable import CodexMenuBar

@MainActor
final class PetUsageBadgePermissionControllerTests: XCTestCase {
    func testAuthorizedStartupRecordsCurrentVersionAndClearsPendingRepair() {
        let (preferences, defaults) = makePreferences(enabled: true)
        defaults.set(
            "0.3.10",
            forKey:
                PetUsageBadgePreferences.pendingPermissionRepairVersionKey
        )

        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: FakeScreenCapturePermissionProvider(
                preflightResult: true,
                requestResult: false
            ),
            currentAppVersion: "0.3.11"
        )

        XCTAssertEqual(controller.status, .authorized)
        XCTAssertEqual(
            preferences.lastAuthorizedAppVersion,
            "0.3.11"
        )
        XCTAssertNil(preferences.pendingPermissionRepairVersion)
    }

    func testFailedPreflightAfterPreviouslyAuthorizedVersionRequiresRepair() {
        let (preferences, defaults) = makePreferences(enabled: true)
        defaults.set(
            "0.3.10",
            forKey: PetUsageBadgePreferences.lastAuthorizedAppVersionKey
        )

        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: FakeScreenCapturePermissionProvider(
                preflightResult: false,
                requestResult: false
            ),
            currentAppVersion: "0.3.11"
        )

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(
            controller.status,
            .repairRequired(reason: .upgradeMismatch)
        )
        XCTAssertEqual(
            preferences.pendingPermissionRepairVersion,
            "0.3.11"
        )
    }

    func testPendingRepairSurvivesRelaunchInSameVersion() {
        let (preferences, defaults) = makePreferences(enabled: false)
        defaults.set(
            "0.3.11",
            forKey:
                PetUsageBadgePreferences.pendingPermissionRepairVersionKey
        )

        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: FakeScreenCapturePermissionProvider(
                preflightResult: false,
                requestResult: false
            ),
            currentAppVersion: "0.3.11"
        )

        XCTAssertEqual(
            controller.status,
            .repairRequired(reason: .upgradeMismatch)
        )
    }

    func testMissingPermissionWithoutHistoryUsesOrdinaryRequiredState() {
        let (preferences, _) = makePreferences(enabled: false)

        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: FakeScreenCapturePermissionProvider(
                preflightResult: false,
                requestResult: false
            ),
            currentAppVersion: "0.3.11"
        )

        XCTAssertEqual(controller.status, .permissionRequired)
        XCTAssertNil(preferences.pendingPermissionRepairVersion)
    }

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

    func testRequestWithoutGrantActivatesFirstReleaseRepairPath() {
        let (preferences, _) = makePreferences(enabled: false)
        let provider = FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: false
        )
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: provider,
            currentAppVersion: "0.3.11"
        )

        controller.setEnabled(true)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(
            controller.status,
            .repairRequired(reason: .requestNotGranted)
        )
        XCTAssertEqual(
            preferences.pendingPermissionRepairVersion,
            "0.3.11"
        )
        XCTAssertTrue(controller.canRepair)
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

    func testSuccessfulResetAndGrantRequiresRestartAndClearsPending() async {
        let (preferences, defaults) = makePreferences(enabled: false)
        defaults.set(
            "0.3.11",
            forKey:
                PetUsageBadgePreferences.pendingPermissionRepairVersionKey
        )
        let resetter = FakeScreenCapturePermissionResetter(
            result: .success(())
        )
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: FakeScreenCapturePermissionProvider(
                preflightResult: false,
                requestResult: true
            ),
            permissionResetter: resetter,
            currentAppVersion: "0.3.11"
        )

        await controller.repairPermission()

        XCTAssertEqual(controller.status, .restartRequired)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(
            preferences.lastAuthorizedAppVersion,
            "0.3.11"
        )
        XCTAssertNil(preferences.pendingPermissionRepairVersion)
    }

    func testResetFailureKeepsTrackingOffAndRepairRetryAvailable() async {
        let (preferences, defaults) = makePreferences(enabled: false)
        defaults.set(
            "0.3.11",
            forKey:
                PetUsageBadgePreferences.pendingPermissionRepairVersionKey
        )
        let provider = FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: true
        )
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: provider,
            permissionResetter: FakeScreenCapturePermissionResetter(
                result: .failure(.nonzeroExit(1))
            ),
            currentAppVersion: "0.3.11"
        )

        await controller.repairPermission()

        XCTAssertEqual(controller.status, .repairFailed)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.canRepair)
        XCTAssertEqual(
            preferences.pendingPermissionRepairVersion,
            "0.3.11"
        )
        XCTAssertEqual(provider.requestCount, 0)
    }

    func testResetSuccessWithoutGrantReturnsToNeutralRepairState() async {
        let (preferences, defaults) = makePreferences(enabled: false)
        defaults.set(
            "0.3.11",
            forKey:
                PetUsageBadgePreferences.pendingPermissionRepairVersionKey
        )
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: FakeScreenCapturePermissionProvider(
                preflightResult: false,
                requestResult: false
            ),
            permissionResetter: FakeScreenCapturePermissionResetter(
                result: .success(())
            ),
            currentAppVersion: "0.3.11"
        )

        await controller.repairPermission()

        XCTAssertEqual(
            controller.status,
            .repairRequired(reason: .requestNotGranted)
        )
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(
            preferences.pendingPermissionRepairVersion,
            "0.3.11"
        )
    }

    func testSecondRepairAttemptIsIgnoredWhileFirstIsSuspended() async {
        let (preferences, defaults) = makePreferences(enabled: false)
        defaults.set(
            "0.3.11",
            forKey:
                PetUsageBadgePreferences.pendingPermissionRepairVersionKey
        )
        let resetter = SuspendedScreenCapturePermissionResetter()
        let controller = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: FakeScreenCapturePermissionProvider(
                preflightResult: false,
                requestResult: true
            ),
            permissionResetter: resetter,
            currentAppVersion: "0.3.11"
        )

        let first = Task {
            await controller.repairPermission()
        }
        await resetter.waitUntilResetStarts()
        let second = Task {
            await controller.repairPermission()
        }
        await second.value

        let count = await resetter.resetCount()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(controller.status, .repairing)

        await resetter.finish(with: .success(()))
        await first.value
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

private actor FakeScreenCapturePermissionResetter:
    ScreenCapturePermissionResetting
{
    let result: Result<Void, ScreenCapturePermissionResetError>

    init(result: Result<Void, ScreenCapturePermissionResetError>) {
        self.result = result
    }

    func reset() async -> Result<Void, ScreenCapturePermissionResetError> {
        result
    }
}

private actor SuspendedScreenCapturePermissionResetter:
    ScreenCapturePermissionResetting
{
    private var count = 0
    private var resetContinuation:
        CheckedContinuation<
            Result<Void, ScreenCapturePermissionResetError>,
            Never
        >?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func reset() async -> Result<Void, ScreenCapturePermissionResetError> {
        count += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        return await withCheckedContinuation { continuation in
            resetContinuation = continuation
        }
    }

    func waitUntilResetStarts() async {
        if count > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resetCount() -> Int {
        count
    }

    func finish(
        with result: Result<Void, ScreenCapturePermissionResetError>
    ) {
        guard let resetContinuation else {
            return
        }
        self.resetContinuation = nil
        resetContinuation.resume(returning: result)
    }
}

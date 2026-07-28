import AppKit
import SwiftUI
import XCTest
import CodexMenuBarCore
@testable import CodexMenuBar

@MainActor
final class DashboardViewSmokeTests: XCTestCase {
    func testPetUsageSettingRendersAsNativeSwitch() {
        let controller = makeSettingsController(
            initiallyEnabled: true,
            preflightResult: true,
            requestResult: false
        )

        let switchControl = firstDescendant(
            of: NSSwitch.self,
            in: controller.view
        )
        XCTAssertNotNil(
            switchControl,
            "The persistent badge setting must use a visually explicit native switch"
        )
        XCTAssertEqual(
            switchControl?.state,
            .on,
            "A persisted enabled preference must visibly reopen in the on state"
        )
    }

    func testMissingPermissionShowsRequiredMessageAndOffSwitch() {
        let controller = makeSettingsController(
            initiallyEnabled: true,
            preflightResult: false,
            requestResult: false
        )

        XCTAssertEqual(
            firstDescendant(of: NSSwitch.self, in: controller.view)?.state,
            .off
        )
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.message(
                for: .permissionRequired,
                language: .english
            ),
            "Screen Recording permission is required"
        )
    }

    func testRequestWithoutGrantShowsRepairMessageAndOffSwitch() {
        let controller = makeSettingsController(
            initiallyEnabled: false,
            preflightResult: false,
            requestResult: false,
            enableAfterInitialization: true
        )

        XCTAssertEqual(
            firstDescendant(of: NSSwitch.self, in: controller.view)?.state,
            .off
        )
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.message(
                for: .repairRequired(reason: .requestNotGranted),
                language: .english
            ),
            "Screen Recording permission was not granted"
        )
    }

    func testUpgradeRepairCopyIsSpecificAndLocalized() {
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.message(
                for: .repairRequired(reason: .upgradeMismatch),
                language: .english
            ),
            "App update requires Screen Recording re-authorization"
        )
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.message(
                for: .repairRequired(reason: .upgradeMismatch),
                language: .simplifiedChinese
            ),
            "App 更新后需要重新授权“屏幕录制”"
        )
    }

    func testRepairConfirmationCopyExplainsTargetedReset() {
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.repairActionTitle(
                language: .english
            ),
            "Reset and Re-authorize"
        )
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.repairConfirmationTitle(
                language: .simplifiedChinese
            ),
            "重置“屏幕录制”权限？"
        )
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.repairConfirmationMessage(
                language: .english
            ),
            "This clears only Codex Menu Bar’s Screen Recording permission record. macOS will ask for permission again."
        )
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.repairConfirmationMessage(
                language: .simplifiedChinese
            ),
            "这只会清除 Codex Menu Bar 的“屏幕录制”权限记录。macOS 随后会再次请求授权。"
        )
    }

    func testUpgradeMismatchExposesRepairActionWithFiniteLayout() {
        let controller = makeSettingsController(
            initiallyEnabled: false,
            preflightResult: false,
            requestResult: false,
            lastAuthorizedAppVersion: "0.3.10",
            currentAppVersion: "0.3.11"
        )

        XCTAssertTrue(
            PetUsageBadgePermissionPresentation.showsRepairAction(
                for: .repairRequired(reason: .upgradeMismatch)
            )
        )
        XCTAssertTrue(
            PetUsageBadgePermissionPresentation.isRepairActionEnabled(
                for: .repairRequired(reason: .upgradeMismatch)
            )
        )
        XCTAssertTrue(controller.view.fittingSize.width.isFinite)
        XCTAssertTrue(controller.view.fittingSize.height.isFinite)
    }

    func testRepairingDisablesRepairButtonAndToggle() async {
        let resetter = SuspendedDashboardPermissionResetter()
        let harness = makeSettingsHarness(
            initiallyEnabled: false,
            preflightResult: false,
            requestResult: false,
            lastAuthorizedAppVersion: "0.3.10",
            currentAppVersion: "0.3.11",
            permissionResetter: resetter
        )

        let repairTask = Task {
            await harness.permissionController.repairPermission()
        }
        await resetter.waitUntilResetStarts()
        await Task.yield()
        harness.hostingController.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(
            PetUsageBadgePermissionPresentation.showsRepairAction(
                for: harness.permissionController.status
            )
        )
        XCTAssertFalse(
            PetUsageBadgePermissionPresentation.isRepairActionEnabled(
                for: harness.permissionController.status
            )
        )
        XCTAssertEqual(
            firstDescendant(
                of: NSSwitch.self,
                in: harness.hostingController.view
            )?.isEnabled,
            false
        )

        await resetter.finish(with: .failure(.nonzeroExit(1)))
        await repairTask.value
    }

    func testGrantedPermissionShowsRestartMessage() {
        let controller = makeSettingsController(
            initiallyEnabled: false,
            preflightResult: false,
            requestResult: true,
            enableAfterInitialization: true
        )

        XCTAssertEqual(
            firstDescendant(of: NSSwitch.self, in: controller.view)?.state,
            .on
        )
        XCTAssertEqual(
            PetUsageBadgePermissionPresentation.message(
                for: .restartRequired,
                language: .english
            ),
            "Restart Codex Menu Bar to finish enabling"
        )
    }

    func testUsageCardExposesTodayInitialTextFromWindowState() {
        let window = WindowUsage(
            label: "5h",
            usedPercent: 28,
            remainingPercent: 72,
            resetsAt: nil,
            todayInitialRemainingPercent: 80,
            didResetToday: true
        )

        XCTAssertEqual(
            UsageCard(title: "Primary", window: window).todayInitialText,
            "Today initial: 80% · reset today"
        )
        XCTAssertNil(UsageCard(title: "Primary", window: nil).todayInitialText)
    }

    func testLoadingFullEmptyAndIndependentFailureStatesHaveFiniteLayout() {
        let states = [
            DashboardSnapshot.loading(at: Date(timeIntervalSince1970: 1)),
            fullSnapshot(),
            DashboardSnapshot(
                rateLimit: .empty("No usage"),
                history: .empty("No history"),
                sessions: .empty("No sessions"),
                warnings: [],
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            DashboardSnapshot(
                rateLimit: .content(usage()),
                history: .failure(DashboardError(message: "History unavailable", detail: "Permission denied")),
                sessions: .empty("No sessions"),
                warnings: [DashboardWarning(path: "/bad.jsonl", line: 4, message: "Malformed JSON")],
                updatedAt: Date(timeIntervalSince1970: 3)
            )
        ]

        for snapshot in states {
            let store = DashboardStore(
                snapshot: snapshot,
                reader: { DashboardSnapshot.loading(at: .distantPast) }
            )
            let controller = NSHostingController(rootView: DashboardView(store: store))
            controller.view.frame = CGRect(x: 0, y: 0, width: 620, height: 520)
            controller.view.layoutSubtreeIfNeeded()
            let size = controller.view.fittingSize
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
    }

    func testNativePetBadgeAndSummaryHaveFiniteFixedLayouts() {
        let store = DashboardStore(
            snapshot: fullSnapshot(),
            reader: { DashboardSnapshot.loading(at: .distantPast) }
        )

        let badge = NSHostingController(
            rootView: PetUsageBadgeView(
                store: store,
                language: .english,
                onClick: {}
            )
        )
        badge.view.frame = CGRect(
            origin: .zero,
            size: PetUsageBadgePlacement.badgeSize
        )
        badge.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(badge.view.fittingSize.width.isFinite)
        XCTAssertTrue(badge.view.fittingSize.height.isFinite)
        XCTAssertEqual(badge.view.fittingSize, PetUsageBadgePlacement.badgeSize)

        let summary = NSHostingController(
            rootView: PetUsageSummaryView(
                store: store,
                language: .english
            )
        )
        summary.view.frame = CGRect(
            origin: .zero,
            size: PetUsageBadgePlacement.summarySize
        )
        summary.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(summary.view.fittingSize.width.isFinite)
        XCTAssertTrue(summary.view.fittingSize.height.isFinite)
        XCTAssertEqual(
            summary.view.fittingSize,
            PetUsageBadgePlacement.summarySize
        )
    }

    private func fullSnapshot() -> DashboardSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let days = (0..<60).map { offset in
            DailyUsage(
                date: start.addingTimeInterval(Double(offset * 86_400)),
                counts: TokenCounts(total: Int64(offset), input: 10, cachedInput: 2, output: 3, reasoning: 1),
                sessions: [],
                heatLevel: offset % 5,
                isFuture: false
            )
        }
        let history = TokenHistorySnapshot(
            interval: DateInterval(start: start, duration: 60 * 86_400),
            days: days,
            heatmapDays: days.map { HeatmapDay(date: $0.date, usage: $0) },
            selectedDefaultDate: days.last!.date
        )
        let session = SessionDisplaySnapshot(
            pid: 42,
            sessionID: "session-1",
            activity: .running,
            taskDescription: "Build the dashboard",
            displayTaskDescription: "Build the dashboard",
            workingDirectory: "/tmp/project",
            sourcePath: "/sessions/one.jsonl",
            lastUpdatedAt: start,
            tokenCounts: TokenCounts(total: 100, input: 70, cachedInput: 20, output: 30, reasoning: 4)
        )
        return DashboardSnapshot(
            rateLimit: .content(usage()),
            history: .content(history),
            sessions: .content([session]),
            warnings: [],
            updatedAt: start
        )
    }

    private func usage() -> UsageSnapshot {
        UsageSnapshot(
            primary: WindowUsage(
                label: "5h",
                usedPercent: 28,
                remainingPercent: 72,
                resetsAt: nil,
                todayInitialRemainingPercent: 80,
                didResetToday: false
            ),
            secondary: WindowUsage(
                label: "7d",
                usedPercent: 40,
                remainingPercent: 60,
                resetsAt: nil,
                todayInitialRemainingPercent: 65,
                didResetToday: true
            ),
            planType: "plus",
            creditsDescription: nil,
            reportedAt: nil,
            sourcePath: "/sessions/one.jsonl"
        )
    }

    private func makeSettingsController(
        initiallyEnabled: Bool,
        preflightResult: Bool,
        requestResult: Bool,
        enableAfterInitialization: Bool = false,
        lastAuthorizedAppVersion: String? = nil,
        currentAppVersion: String = "0.3.11"
    ) -> NSHostingController<DashboardView> {
        makeSettingsHarness(
            initiallyEnabled: initiallyEnabled,
            preflightResult: preflightResult,
            requestResult: requestResult,
            enableAfterInitialization: enableAfterInitialization,
            lastAuthorizedAppVersion: lastAuthorizedAppVersion,
            currentAppVersion: currentAppVersion
        ).hostingController
    }

    private func makeSettingsHarness(
        initiallyEnabled: Bool,
        preflightResult: Bool,
        requestResult: Bool,
        enableAfterInitialization: Bool = false,
        lastAuthorizedAppVersion: String? = nil,
        currentAppVersion: String = "0.3.11",
        permissionResetter: any ScreenCapturePermissionResetting =
            SystemScreenCapturePermissionResetter()
    ) -> DashboardSettingsHarness {
        let defaultsName = "DashboardViewSmokeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defaults.set(true, forKey: PetUsageBadgePreferences.migrationKey)
        defaults.set(
            initiallyEnabled,
            forKey: PetUsageBadgePreferences.enabledKey
        )
        defaults.set(
            AppLanguagePreference.english.rawValue,
            forKey: AppLanguagePreferences.selectionKey
        )
        let preferences = PetUsageBadgePreferences(defaults: defaults)
        preferences.lastAuthorizedAppVersion = lastAuthorizedAppVersion
        let permissionController = PetUsageBadgePermissionController(
            preferences: preferences,
            permissionProvider: DashboardTestScreenCapturePermissionProvider(
                preflightResult: preflightResult,
                requestResult: requestResult
            ),
            permissionResetter: permissionResetter,
            currentAppVersion: currentAppVersion
        )
        if enableAfterInitialization {
            permissionController.setEnabled(true)
        }
        let store = DashboardStore(
            snapshot: fullSnapshot(),
            reader: { DashboardSnapshot.loading(at: .distantPast) }
        )
        let controller = NSHostingController(
            rootView: DashboardView(
                store: store,
                petUsageBadgePermissionController: permissionController,
                languagePreferences: AppLanguagePreferences(defaults: defaults)
            )
        )
        controller.view.frame = CGRect(x: 0, y: 0, width: 620, height: 520)
        controller.view.layoutSubtreeIfNeeded()
        return DashboardSettingsHarness(
            hostingController: controller,
            permissionController: permissionController
        )
    }

    private func firstDescendant<T: NSView>(
        of type: T.Type,
        in view: NSView,
        where predicate: @escaping (T) -> Bool = { _ in true }
    ) -> T? {
        if let match = view as? T, predicate(match) {
            return match
        }
        return view.subviews.lazy.compactMap {
            self.firstDescendant(of: type, in: $0, where: predicate)
        }.first
    }
}

@MainActor
private struct DashboardSettingsHarness {
    let hostingController: NSHostingController<DashboardView>
    let permissionController: PetUsageBadgePermissionController
}

@MainActor
private final class DashboardTestScreenCapturePermissionProvider:
    ScreenCapturePermissionProviding
{
    let preflightResult: Bool
    let requestResult: Bool

    init(preflightResult: Bool, requestResult: Bool) {
        self.preflightResult = preflightResult
        self.requestResult = requestResult
    }

    func preflight() -> Bool {
        preflightResult
    }

    func request() -> Bool {
        requestResult
    }
}

private actor SuspendedDashboardPermissionResetter:
    ScreenCapturePermissionResetting
{
    private var resetContinuation:
        CheckedContinuation<Result<Void, ScreenCapturePermissionResetError>, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func reset() async -> Result<Void, ScreenCapturePermissionResetError> {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        return await withCheckedContinuation { continuation in
            resetContinuation = continuation
        }
    }

    func waitUntilResetStarts() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(
        with result: Result<Void, ScreenCapturePermissionResetError>
    ) {
        resetContinuation?.resume(returning: result)
        resetContinuation = nil
    }
}

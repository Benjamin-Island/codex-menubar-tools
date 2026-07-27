import Combine
import CoreGraphics
import Foundation

enum PetUsageBadgePermissionRepairReason: Equatable {
    case upgradeMismatch
    case requestNotGranted
}

enum PetUsageBadgePermissionStatus: Equatable {
    case authorized
    case permissionRequired
    case denied
    case repairRequired(reason: PetUsageBadgePermissionRepairReason)
    case repairing
    case repairFailed
    case restartRequired
}

enum PetUsageBadgePermissionPresentation {
    static func message(
        for status: PetUsageBadgePermissionStatus,
        language: AppDisplayLanguage
    ) -> String? {
        switch status {
        case .authorized:
            nil
        case .permissionRequired:
            appText(
                "Screen Recording permission is required",
                "需要“屏幕录制”权限",
                language: language
            )
        case .denied:
            appText(
                "Screen Recording permission was denied",
                "“屏幕录制”权限已被拒绝",
                language: language
            )
        case .repairRequired:
            appText(
                "Screen Recording permission is required",
                "需要“屏幕录制”权限",
                language: language
            )
        case .repairing:
            appText(
                "Repairing Screen Recording permission",
                "正在修复“屏幕录制”权限",
                language: language
            )
        case .repairFailed:
            appText(
                "Screen Recording permission repair failed",
                "“屏幕录制”权限修复失败",
                language: language
            )
        case .restartRequired:
            appText(
                "Restart Codex Menu Bar to finish enabling",
                "请重启 Codex Menu Bar 以完成启用",
                language: language
            )
        }
    }
}

@MainActor
protocol ScreenCapturePermissionProviding: AnyObject {
    func preflight() -> Bool
    func request() -> Bool
}

@MainActor
final class SystemScreenCapturePermissionProvider:
    ScreenCapturePermissionProviding
{
    func preflight() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

@MainActor
final class PetUsageBadgePermissionController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var status: PetUsageBadgePermissionStatus

    var canTrack: Bool {
        isEnabled && status == .authorized
    }

    var canRepair: Bool {
        if case .repairRequired = status {
            true
        } else if status == .repairFailed {
            true
        } else {
            false
        }
    }

    var isRepairing: Bool {
        status == .repairing
    }

    private let preferences: PetUsageBadgePreferences
    private let permissionProvider: any ScreenCapturePermissionProviding
    private let permissionResetter: any ScreenCapturePermissionResetting
    private let currentAppVersion: String

    init(
        preferences: PetUsageBadgePreferences,
        permissionProvider: any ScreenCapturePermissionProviding =
            SystemScreenCapturePermissionProvider(),
        permissionResetter: any ScreenCapturePermissionResetting =
            SystemScreenCapturePermissionResetter(),
        currentAppVersion: String =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown"
    ) {
        self.preferences = preferences
        self.permissionProvider = permissionProvider
        self.permissionResetter = permissionResetter
        self.currentAppVersion = currentAppVersion

        if permissionProvider.preflight() {
            isEnabled = preferences.isEnabled
            status = .authorized
            preferences.lastAuthorizedAppVersion = currentAppVersion
            preferences.pendingPermissionRepairVersion = nil
        } else if
            preferences.pendingPermissionRepairVersion == currentAppVersion
                || preferences.lastAuthorizedAppVersion.map({
                    $0 != currentAppVersion
                }) == true
        {
            isEnabled = false
            status = .repairRequired(reason: .upgradeMismatch)
            preferences.isEnabled = false
            preferences.pendingPermissionRepairVersion = currentAppVersion
        } else {
            isEnabled = false
            status = .permissionRequired
            if preferences.isEnabled {
                preferences.isEnabled = false
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            isEnabled = false
            preferences.isEnabled = false
            return
        }

        if permissionProvider.preflight() {
            status = .authorized
            isEnabled = true
            preferences.isEnabled = true
            preferences.lastAuthorizedAppVersion = currentAppVersion
            preferences.pendingPermissionRepairVersion = nil
            return
        }

        if permissionProvider.request() {
            status = .restartRequired
            isEnabled = true
            preferences.isEnabled = true
            preferences.lastAuthorizedAppVersion = currentAppVersion
            preferences.pendingPermissionRepairVersion = nil
        } else {
            status = .repairRequired(reason: .requestNotGranted)
            isEnabled = false
            preferences.isEnabled = false
            preferences.pendingPermissionRepairVersion = currentAppVersion
        }
    }

    func repairPermission() async {
        guard canRepair, !isRepairing else {
            return
        }

        status = .repairing
        isEnabled = false
        preferences.isEnabled = false
        preferences.pendingPermissionRepairVersion = currentAppVersion

        switch await permissionResetter.reset() {
        case .failure:
            status = .repairFailed
        case .success:
            if permissionProvider.request() {
                status = .restartRequired
                isEnabled = true
                preferences.isEnabled = true
                preferences.lastAuthorizedAppVersion = currentAppVersion
                preferences.pendingPermissionRepairVersion = nil
            } else {
                status = .repairRequired(reason: .requestNotGranted)
            }
        }
    }
}

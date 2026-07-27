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
        case let .repairRequired(reason):
            switch reason {
            case .upgradeMismatch:
                appText(
                    "App update requires Screen Recording re-authorization",
                    "App 更新后需要重新授权“屏幕录制”",
                    language: language
                )
            case .requestNotGranted:
                appText(
                    "Screen Recording permission was not granted",
                    "尚未授予“屏幕录制”权限",
                    language: language
                )
            }
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

    static func repairActionTitle(
        language: AppDisplayLanguage
    ) -> String {
        appText(
            "Reset and Re-authorize",
            "重置并重新授权",
            language: language
        )
    }

    static func repairConfirmationTitle(
        language: AppDisplayLanguage
    ) -> String {
        appText(
            "Reset Screen Recording permission?",
            "重置“屏幕录制”权限？",
            language: language
        )
    }

    static func repairConfirmationMessage(
        language: AppDisplayLanguage
    ) -> String {
        appText(
            "This clears only Codex Menu Bar’s Screen Recording permission record. macOS will ask for permission again.",
            "这只会清除 Codex Menu Bar 的“屏幕录制”权限记录。macOS 随后会再次请求授权。",
            language: language
        )
    }

    static func repairConfirmationActionTitle(
        language: AppDisplayLanguage
    ) -> String {
        appText("Reset Permission", "重置权限", language: language)
    }

    static func repairConfirmationCancelTitle(
        language: AppDisplayLanguage
    ) -> String {
        appText("Cancel", "取消", language: language)
    }

    static func showsRepairAction(
        for status: PetUsageBadgePermissionStatus
    ) -> Bool {
        switch status {
        case .repairRequired, .repairing, .repairFailed:
            true
        case .authorized, .permissionRequired, .restartRequired:
            false
        }
    }

    static func isRepairActionEnabled(
        for status: PetUsageBadgePermissionStatus
    ) -> Bool {
        switch status {
        case .repairRequired, .repairFailed:
            true
        case .authorized, .permissionRequired, .repairing, .restartRequired:
            false
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

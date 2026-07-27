import Combine
import CoreGraphics
import Foundation

enum PetUsageBadgePermissionStatus: Equatable {
    case authorized
    case permissionRequired
    case denied
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

    private let preferences: PetUsageBadgePreferences
    private let permissionProvider: any ScreenCapturePermissionProviding

    init(
        preferences: PetUsageBadgePreferences,
        permissionProvider: any ScreenCapturePermissionProviding =
            SystemScreenCapturePermissionProvider()
    ) {
        self.preferences = preferences
        self.permissionProvider = permissionProvider

        if permissionProvider.preflight() {
            isEnabled = preferences.isEnabled
            status = .authorized
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
            return
        }

        if permissionProvider.request() {
            status = .restartRequired
            isEnabled = true
            preferences.isEnabled = true
        } else {
            status = .denied
            isEnabled = false
            preferences.isEnabled = false
        }
    }
}

import Foundation

@MainActor
final class PetUsageBadgePreferences: ObservableObject {
    static let enabledKey = "petUsageBadge.enabled"
    static let migrationKey = "petUsageBadge.migratedFromPetIsland"
    static let lastAuthorizedAppVersionKey =
        "petUsageBadge.lastAuthorizedAppVersion"
    static let pendingPermissionRepairVersionKey =
        "petUsageBadge.pendingPermissionRepairVersion"
    private static let legacyEnabledKey = "petIsland.enabled"

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    private let defaults: UserDefaults

    var lastAuthorizedAppVersion: String? {
        get { defaults.string(forKey: Self.lastAuthorizedAppVersionKey) }
        set {
            if let newValue {
                defaults.set(
                    newValue,
                    forKey: Self.lastAuthorizedAppVersionKey
                )
            } else {
                defaults.removeObject(
                    forKey: Self.lastAuthorizedAppVersionKey
                )
            }
        }
    }

    var pendingPermissionRepairVersion: String? {
        get {
            defaults.string(forKey: Self.pendingPermissionRepairVersionKey)
        }
        set {
            if let newValue {
                defaults.set(
                    newValue,
                    forKey: Self.pendingPermissionRepairVersionKey
                )
            } else {
                defaults.removeObject(
                    forKey: Self.pendingPermissionRepairVersionKey
                )
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.bool(forKey: Self.migrationKey) {
            isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        } else {
            isEnabled =
                defaults.object(forKey: Self.legacyEnabledKey) as? Bool ?? true
            defaults.set(isEnabled, forKey: Self.enabledKey)
            defaults.set(true, forKey: Self.migrationKey)
        }
    }
}

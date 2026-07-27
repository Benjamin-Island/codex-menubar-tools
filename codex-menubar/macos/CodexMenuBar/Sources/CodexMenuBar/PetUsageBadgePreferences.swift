import Foundation

@MainActor
final class PetUsageBadgePreferences: ObservableObject {
    static let enabledKey = "petUsageBadge.enabled"
    static let migrationKey = "petUsageBadge.migratedFromPetIsland"
    private static let legacyEnabledKey = "petIsland.enabled"

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    private let defaults: UserDefaults

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

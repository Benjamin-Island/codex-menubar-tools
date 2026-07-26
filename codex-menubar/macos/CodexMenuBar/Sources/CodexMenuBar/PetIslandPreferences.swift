import Foundation

@MainActor
final class PetIslandPreferences: ObservableObject {
    static let enabledKey = "petIsland.enabled"
    static let selectedPetKey = "petIsland.selectedPetID"
    static let explicitSelectionKey = "petIsland.hasExplicitSelection"
    static let presentationKey = "petIsland.presentationMode"
    static let petScaleKey = "petIsland.petScalePercent"
    static let defaultPetScale = 100.0
    static let petScaleRange = 75.0 ... 300.0

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published var petScalePercent: Double {
        didSet { defaults.set(petScalePercent, forKey: Self.petScaleKey) }
    }

    @Published var selectedPetID: String {
        didSet { defaults.set(selectedPetID, forKey: Self.selectedPetKey) }
    }

    @Published private(set) var followsLocalPet: Bool
    @Published private(set) var pets: [CodexPet]

    private let defaults: UserDefaults
    private var localSelectedPetID: String?

    init(
        pets: [CodexPet] = CodexPetCatalog().load(),
        defaults: UserDefaults = .standard,
        localSelectedPetID: String? = CodexPetSelectionReader().selectedPetID()
    ) {
        self.pets = pets
        self.defaults = defaults
        self.localSelectedPetID = localSelectedPetID
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let savedScale = defaults.object(forKey: Self.petScaleKey) as? Double
            ?? Self.defaultPetScale
        petScalePercent = min(
            Self.petScaleRange.upperBound,
            max(Self.petScaleRange.lowerBound, savedScale)
        )
        defaults.removeObject(forKey: Self.presentationKey)

        let savedID = defaults.string(forKey: Self.selectedPetKey)
        let hasExplicitSelection = defaults.bool(forKey: Self.explicitSelectionKey)
        followsLocalPet = !hasExplicitSelection
        if hasExplicitSelection,
           let savedID,
           pets.contains(where: { $0.id == savedID }) {
            selectedPetID = savedID
        } else {
            selectedPetID = Self.recommendedPet(
                in: pets,
                localSelectedPetID: localSelectedPetID
            )?.id ?? ""
        }
    }

    var selectedPet: CodexPet? {
        pets.first(where: { $0.id == selectedPetID }) ?? pets.first
    }

    func selectPet(id: String) {
        guard pets.contains(where: { $0.id == id }) else { return }
        defaults.set(true, forKey: Self.explicitSelectionKey)
        followsLocalPet = false
        selectedPetID = id
    }

    func followLocalConfiguration() {
        defaults.set(false, forKey: Self.explicitSelectionKey)
        followsLocalPet = true
        selectedPetID = Self.recommendedPet(
            in: pets,
            localSelectedPetID: localSelectedPetID
        )?.id ?? ""
    }

    func setFollowsLocalPet(_ follows: Bool) {
        if follows {
            followLocalConfiguration()
        } else {
            defaults.set(true, forKey: Self.explicitSelectionKey)
            followsLocalPet = false
        }
    }

    func reloadLocalConfiguration(
        pets: [CodexPet],
        localSelectedPetID: String?
    ) {
        self.pets = pets
        self.localSelectedPetID = localSelectedPetID

        if followsLocalPet {
            selectedPetID = Self.recommendedPet(
                in: pets,
                localSelectedPetID: localSelectedPetID
            )?.id ?? ""
        } else if !pets.contains(where: { $0.id == selectedPetID }) {
            selectedPetID = pets.first?.id ?? ""
        }
    }

    static func recommendedPet(
        in pets: [CodexPet],
        localSelectedPetID: String? = nil
    ) -> CodexPet? {
        if let localSelectedPetID,
           let selected = pets.first(where: { $0.id == localSelectedPetID })
                ?? pets.first(where: {
                    $0.manifestID == localSelectedPetID && $0.isCanonicalPackage
                }) {
            return selected
        }
        let canonical = pets.filter(\.isCanonicalPackage)
        let candidates = canonical.isEmpty ? pets : canonical
        return candidates.max {
            if $0.manifestModifiedAt == $1.manifestModifiedAt {
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
            return $0.manifestModifiedAt < $1.manifestModifiedAt
        }
    }
}

struct CodexPetSelectionReader {
    let configURL: URL

    init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    ) {
        self.configURL = configURL
    }

    func selectedPetID() -> String? {
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("selected-avatar-id"),
                  let separator = line.firstIndex(of: "=")
            else {
                continue
            }
            var value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if let comment = value.firstIndex(of: "#") {
                value = String(value[..<comment]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { return nil }
            return value.split(separator: ":", maxSplits: 1).last.map(String.init)
        }
        return nil
    }
}

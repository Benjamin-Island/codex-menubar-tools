import Combine
import Foundation

enum PetPresentationPreference: String, CaseIterable, Identifiable {
    case automatic
    case notch
    case floating

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .notch: "Notch Bar"
        case .floating: "Floating Pet"
        }
    }
}

@MainActor
final class PetIslandPreferences: ObservableObject {
    static let enabledKey = "petIsland.enabled"
    static let selectedPetKey = "petIsland.selectedPetID"
    static let explicitSelectionKey = "petIsland.hasExplicitSelection"
    static let presentationKey = "petIsland.presentationMode"

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published var selectedPetID: String {
        didSet { defaults.set(selectedPetID, forKey: Self.selectedPetKey) }
    }

    @Published var presentationMode: PetPresentationPreference {
        didSet { defaults.set(presentationMode.rawValue, forKey: Self.presentationKey) }
    }

    let pets: [CodexPet]

    private let defaults: UserDefaults

    init(
        pets: [CodexPet] = CodexPetCatalog().load(),
        defaults: UserDefaults = .standard
    ) {
        self.pets = pets
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        presentationMode = PetPresentationPreference(
            rawValue: defaults.string(forKey: Self.presentationKey) ?? ""
        ) ?? .automatic

        let savedID = defaults.string(forKey: Self.selectedPetKey)
        let hasExplicitSelection = defaults.bool(forKey: Self.explicitSelectionKey)
        if hasExplicitSelection,
           let savedID,
           pets.contains(where: { $0.id == savedID }) {
            selectedPetID = savedID
        } else {
            selectedPetID = Self.recommendedPet(in: pets)?.id ?? ""
        }
    }

    var selectedPet: CodexPet? {
        pets.first(where: { $0.id == selectedPetID }) ?? pets.first
    }

    func selectPet(id: String) {
        guard pets.contains(where: { $0.id == id }) else { return }
        defaults.set(true, forKey: Self.explicitSelectionKey)
        selectedPetID = id
    }

    func followLocalConfiguration() {
        defaults.set(false, forKey: Self.explicitSelectionKey)
        selectedPetID = Self.recommendedPet(in: pets)?.id ?? ""
    }

    static func recommendedPet(in pets: [CodexPet]) -> CodexPet? {
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

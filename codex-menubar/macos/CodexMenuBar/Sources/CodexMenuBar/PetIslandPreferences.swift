import Combine
import Foundation

@MainActor
final class PetIslandPreferences: ObservableObject {
    static let enabledKey = "petIsland.enabled"
    static let selectedPetKey = "petIsland.selectedPetID"

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published var selectedPetID: String {
        didSet { defaults.set(selectedPetID, forKey: Self.selectedPetKey) }
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

        let savedID = defaults.string(forKey: Self.selectedPetKey)
        if let savedID, pets.contains(where: { $0.id == savedID }) {
            selectedPetID = savedID
        } else {
            selectedPetID = pets.first?.id ?? ""
        }
    }

    var selectedPet: CodexPet? {
        pets.first(where: { $0.id == selectedPetID }) ?? pets.first
    }
}

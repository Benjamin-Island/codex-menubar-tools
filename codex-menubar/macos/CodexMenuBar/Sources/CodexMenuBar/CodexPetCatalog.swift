import Foundation

struct CodexPet: Identifiable, Equatable, Sendable {
    let id: String
    let manifestID: String?
    let displayName: String
    let description: String?
    let spriteVersionNumber: Int
    let spritesheetURL: URL
    let manifestModifiedAt: Date

    var isCanonicalPackage: Bool {
        manifestID == nil || manifestID == id
    }
}

struct CodexPetCatalog {
    let roots: [URL]
    private let fileManager: FileManager

    init(
        roots: [URL] = Self.defaultRoots(),
        fileManager: FileManager = .default
    ) {
        self.roots = roots
        self.fileManager = fileManager
    }

    func load() -> [CodexPet] {
        var seenIDs: Set<String> = []
        var pets: [CodexPet] = []

        for root in roots {
            guard let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let pet = loadPet(in: directory), seenIDs.insert(pet.id).inserted else {
                    continue
                }
                pets.append(pet)
            }
        }

        return pets.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func defaultRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".codex/pets", isDirectory: true),
            homeDirectory.appendingPathComponent(
                "Library/Application Support/Codex/pets",
                isDirectory: true
            ),
            homeDirectory.appendingPathComponent(
                "Library/Application Support/ChatGPT/pets",
                isDirectory: true
            )
        ]
    }

    private func loadPet(in directory: URL) -> CodexPet? {
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CodexPetManifest.self, from: data)
        else {
            return nil
        }

        let directoryURL = directory.standardizedFileURL
        let spriteURL = directoryURL
            .appendingPathComponent(manifest.spritesheetPath)
            .standardizedFileURL
        let directoryPrefix = directoryURL.path.hasSuffix("/")
            ? directoryURL.path
            : directoryURL.path + "/"
        guard spriteURL.path.hasPrefix(directoryPrefix),
              fileManager.fileExists(atPath: spriteURL.path)
        else {
            return nil
        }

        let id = directory.lastPathComponent
        let modifiedAt = (try? manifestURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? .distantPast
        return CodexPet(
            id: id,
            manifestID: manifest.id?.trimmedNonEmpty,
            displayName: manifest.displayName?.trimmedNonEmpty ?? id,
            description: manifest.description?.trimmedNonEmpty,
            spriteVersionNumber: manifest.spriteVersionNumber,
            spritesheetURL: spriteURL,
            manifestModifiedAt: modifiedAt
        )
    }
}

private struct CodexPetManifest: Decodable {
    let id: String?
    let displayName: String?
    let description: String?
    let spriteVersionNumber: Int
    let spritesheetPath: String

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case description
        case spriteVersionNumber
        case spritesheetPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        spriteVersionNumber = try container.decodeIfPresent(
            Int.self,
            forKey: .spriteVersionNumber
        ) ?? 1
        spritesheetPath = try container.decodeIfPresent(
            String.self,
            forKey: .spritesheetPath
        ) ?? "spritesheet.webp"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

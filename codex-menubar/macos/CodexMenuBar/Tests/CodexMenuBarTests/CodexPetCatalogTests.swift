import Foundation
import XCTest
@testable import CodexMenuBar

final class CodexPetCatalogTests: XCTestCase {
    func testLoadsManifestDefaultsAndDeduplicatesRootsByPetID() throws {
        let temporary = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let firstRoot = temporary.appendingPathComponent("first", isDirectory: true)
        let secondRoot = temporary.appendingPathComponent("second", isDirectory: true)

        try writePet(
            id: "scout",
            manifest: #"{"displayName":"Scout","description":"Newsroom fox"}"#,
            root: firstRoot
        )
        try writePet(
            id: "scout",
            manifest: #"{"displayName":"Duplicate Scout"}"#,
            root: secondRoot
        )
        try writePet(
            id: "penguin",
            manifest: #"{"displayName":"Penguin","spriteVersionNumber":2,"spritesheetPath":"pet.webp"}"#,
            root: secondRoot,
            spriteName: "pet.webp"
        )

        let pets = CodexPetCatalog(roots: [firstRoot, secondRoot]).load()

        XCTAssertEqual(pets.map(\.id), ["penguin", "scout"])
        XCTAssertEqual(pets.first(where: { $0.id == "scout" })?.displayName, "Scout")
        XCTAssertEqual(pets.first(where: { $0.id == "scout" })?.spriteVersionNumber, 1)
        XCTAssertEqual(pets.first(where: { $0.id == "penguin" })?.spriteVersionNumber, 2)
    }

    func testRejectsSpritesheetPathOutsidePetDirectory() throws {
        let temporary = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("pets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("outside.webp"))
        try writePet(
            id: "unsafe",
            manifest: #"{"displayName":"Unsafe","spritesheetPath":"../outside.webp"}"#,
            root: root,
            createSprite: false
        )

        XCTAssertTrue(CodexPetCatalog(roots: [root]).load().isEmpty)
    }

    func testDefaultRootsCoverCodexAndDesktopLocations() {
        let home = URL(fileURLWithPath: "/Users/test")
        let paths = CodexPetCatalog.defaultRoots(homeDirectory: home).map(\.path)

        XCTAssertEqual(
            paths,
            [
                "/Users/test/.codex/pets",
                "/Users/test/Library/Application Support/Codex/pets",
                "/Users/test/Library/Application Support/ChatGPT/pets"
            ]
        )
    }

    private func writePet(
        id: String,
        manifest: String,
        root: URL,
        spriteName: String = "spritesheet.webp",
        createSprite: Bool = true
    ) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("pet.json"))
        if createSprite {
            try Data().write(to: directory.appendingPathComponent(spriteName))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

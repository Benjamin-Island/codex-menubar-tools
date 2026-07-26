import Foundation
import XCTest
@testable import CodexMenuBar

@MainActor
final class AppLanguagePreferencesTests: XCTestCase {
    func testDefaultsToSystemAndPersistsExplicitLanguage() {
        let suiteName = "AppLanguagePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppLanguagePreferences(defaults: defaults)
        XCTAssertEqual(preferences.selection, .system)

        preferences.selection = .simplifiedChinese
        XCTAssertEqual(
            AppLanguagePreferences(defaults: defaults).selection,
            .simplifiedChinese
        )
    }

    func testSystemLanguageResolutionSupportsChineseAndEnglish() {
        XCTAssertEqual(
            AppLanguagePreference.system.resolve(preferredLanguages: ["zh-Hans-CN"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLanguagePreference.system.resolve(preferredLanguages: ["en-US"]),
            .english
        )
        XCTAssertEqual(
            AppLanguagePreference.english.resolve(preferredLanguages: ["zh-Hans"]),
            .english
        )
    }
}

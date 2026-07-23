import Combine
import Foundation
import SwiftUI

enum AppDisplayLanguage: Equatable {
    case english
    case simplifiedChinese
}

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统 / System"
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }

    func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> AppDisplayLanguage {
        switch self {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .system:
            return preferredLanguages.first?.lowercased().hasPrefix("zh") == true
                ? .simplifiedChinese
                : .english
        }
    }
}

@MainActor
final class AppLanguagePreferences: ObservableObject {
    static let selectionKey = "app.language"

    @Published var selection: AppLanguagePreference {
        didSet { defaults.set(selection.rawValue, forKey: Self.selectionKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppLanguagePreference(
            rawValue: defaults.string(forKey: Self.selectionKey) ?? ""
        ) ?? .system
    }

    var resolvedLanguage: AppDisplayLanguage {
        selection.resolve()
    }
}

private struct AppDisplayLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguagePreference.system.resolve()
}

extension EnvironmentValues {
    var appDisplayLanguage: AppDisplayLanguage {
        get { self[AppDisplayLanguageKey.self] }
        set { self[AppDisplayLanguageKey.self] = newValue }
    }
}

func appText(
    _ english: String,
    _ simplifiedChinese: String,
    language: AppDisplayLanguage
) -> String {
    language == .simplifiedChinese ? simplifiedChinese : english
}

func localizedDashboardMessage(
    _ message: String,
    language: AppDisplayLanguage
) -> String {
    guard language == .simplifiedChinese else { return message }
    switch message {
    case "No active Codex sessions are running.":
        return "当前没有正在运行的 Codex 任务。"
    case "No Token history found yet.":
        return "暂未找到 Token 历史。"
    case "No rate limit event found yet. Open or use Codex once to generate usage data.":
        return "暂未找到额度记录，请先打开或使用一次 Codex。"
    case "Unable to read Codex session logs":
        return "无法读取 Codex 会话日志"
    case "Unable to scan Codex CLI processes":
        return "无法扫描 Codex CLI 进程"
    default:
        return message
    }
}

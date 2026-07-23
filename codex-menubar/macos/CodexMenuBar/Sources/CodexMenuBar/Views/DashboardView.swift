import AppKit
import SwiftUI
import CodexMenuBarCore

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var languagePreferences: AppLanguagePreferences
    let petIslandPreferences: PetIslandPreferences?
    @Environment(\.appDisplayLanguage) private var language

    init(
        store: DashboardStore,
        petIslandPreferences: PetIslandPreferences? = nil,
        languagePreferences: AppLanguagePreferences = AppLanguagePreferences()
    ) {
        self.store = store
        self.petIslandPreferences = petIslandPreferences
        self.languagePreferences = languagePreferences
    }

    private var sessionCount: Int {
        guard case let .content(sessions) = store.snapshot.sessions else { return 0 }
        return sessions.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.snapshot.warnings.isEmpty {
                PartialWarningBanner(count: store.snapshot.warnings.count)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Group {
                switch store.selectedTab {
                case .overview: OverviewView(store: store)
                case .history: HistoryView(store: store)
                case .sessions: SessionsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 620, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.appDisplayLanguage, languagePreferences.resolvedLanguage)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Codex Menu Bar", systemImage: "terminal.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(text("Updated", "更新于")) \(store.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(text("Dashboard section", "面板栏目"), selection: $store.selectedTab) {
                Text(text("Overview", "概览")).tag(DashboardTab.overview)
                Text(text("History", "历史")).tag(DashboardTab.history)
                Text("\(text("Sessions", "任务")) \(sessionCount)").tag(DashboardTab.sessions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            Button {
                store.refresh()
            } label: {
                Label(
                    store.isRefreshing
                        ? text("Refreshing", "刷新中")
                        : text("Refresh", "刷新"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(store.isRefreshing)
            if let petIslandPreferences {
                PetIslandSettingsControl(preferences: petIslandPreferences)
            }
            languageControl
            Spacer()
            Label(text("Local logs · Read-only", "本地日志 · 只读"), systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(text("Quit", "退出")) { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var languageControl: some View {
        Picker(
            text("Language", "语言"),
            selection: Binding(
                get: { languagePreferences.resolvedLanguage },
                set: { language in
                    languagePreferences.selection = language == .simplifiedChinese
                        ? .simplifiedChinese
                        : .english
                }
            )
        ) {
            Text("中").tag(AppDisplayLanguage.simplifiedChinese)
            Text("EN").tag(AppDisplayLanguage.english)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 74)
        .help(text("Switch language", "切换语言"))
    }

    private func text(_ english: String, _ chinese: String) -> String {
        appText(english, chinese, language: languagePreferences.resolvedLanguage)
    }
}

private struct PetIslandSettingsControl: View {
    @ObservedObject var preferences: PetIslandPreferences
    @Environment(\.appDisplayLanguage) private var language

    var body: some View {
        Menu {
            Toggle(text("Show Pet Island", "显示宠物岛"), isOn: $preferences.isEnabled)
            if !preferences.pets.isEmpty {
                Divider()
                Toggle(
                    text("Follow Local Pet", "跟随本地宠物形象"),
                    isOn: Binding(
                        get: { preferences.followsLocalPet },
                        set: { preferences.setFollowsLocalPet($0) }
                    )
                )
                Divider()
                ForEach(preferences.pets) { pet in
                    Button {
                        preferences.selectPet(id: pet.id)
                        preferences.isEnabled = true
                    } label: {
                        if pet.id == preferences.selectedPetID {
                            Label(pet.displayName, systemImage: "checkmark")
                        } else {
                            Text(pet.displayName)
                        }
                    }
                }
            } else {
                Text(text("No custom Codex pets found", "未找到 Codex 自定义宠物"))
            }
        } label: {
            Label(text("Pet Island", "宠物岛"), systemImage: "pawprint.fill")
        }
        .help(text("Choose a custom pet from ~/.codex/pets", "从 ~/.codex/pets 选择自定义宠物"))
    }

    private func text(_ english: String, _ chinese: String) -> String {
        appText(english, chinese, language: language)
    }
}

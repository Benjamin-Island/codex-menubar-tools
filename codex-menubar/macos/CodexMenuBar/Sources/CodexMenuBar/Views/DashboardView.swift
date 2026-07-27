import AppKit
import SwiftUI
import CodexMenuBarCore

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var languagePreferences: AppLanguagePreferences
    let petUsageBadgePermissionController:
        PetUsageBadgePermissionController?
    @Environment(\.appDisplayLanguage) private var language

    init(
        store: DashboardStore,
        petUsageBadgePermissionController:
            PetUsageBadgePermissionController? = nil,
        languagePreferences: AppLanguagePreferences = AppLanguagePreferences()
    ) {
        self.store = store
        self.petUsageBadgePermissionController =
            petUsageBadgePermissionController
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
        VStack(spacing: 6) {
            if let petUsageBadgePermissionController {
                PetUsageBadgePermissionMessage(
                    permissionController:
                        petUsageBadgePermissionController
                )
            }
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
                if let petUsageBadgePermissionController {
                    PetUsageBadgeSettingsControl(
                        permissionController:
                            petUsageBadgePermissionController
                    )
                }
                languageControl
                Spacer()
                Label(text("Local logs · Read-only", "本地日志 · 只读"), systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(text("Quit", "退出")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .controlSize(.small)
        }
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

private struct PetUsageBadgeSettingsControl: View {
    @ObservedObject var permissionController:
        PetUsageBadgePermissionController
    @Environment(\.appDisplayLanguage) private var language

    var body: some View {
        Toggle(
            text(
                "Show Usage by Codex Pet",
                "在 Codex 宠物旁显示额度"
            ),
            isOn: Binding(
                get: { permissionController.isEnabled },
                set: { permissionController.setEnabled($0) }
            )
        )
        .toggleStyle(.switch)
        .disabled(permissionController.isRepairing)
        .help(
            text(
                "Shown only while the Codex native Pet is visible",
                "仅在 Codex 原生宠物可见时显示"
            )
        )
    }

    private func text(_ english: String, _ chinese: String) -> String {
        appText(english, chinese, language: language)
    }
}

private struct PetUsageBadgePermissionMessage: View {
    @ObservedObject var permissionController:
        PetUsageBadgePermissionController
    @Environment(\.appDisplayLanguage) private var language
    @State private var isShowingRepairConfirmation = false

    var body: some View {
        if let message {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                    Text(message)
                    Spacer()
                }
                if showsRepairAction {
                    HStack {
                        Spacer()
                        Button(
                            PetUsageBadgePermissionPresentation
                                .repairActionTitle(language: language)
                        ) {
                            isShowingRepairConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            !PetUsageBadgePermissionPresentation
                                .isRepairActionEnabled(
                                    for: permissionController.status
                                )
                        )
                    }
                    .controlSize(.small)
                }
            }
            .font(.caption)
            .foregroundStyle(messageColor)
            .frame(maxWidth: .infinity)
            .alert(
                PetUsageBadgePermissionPresentation
                    .repairConfirmationTitle(language: language),
                isPresented: $isShowingRepairConfirmation
            ) {
                Button(
                    PetUsageBadgePermissionPresentation
                        .repairConfirmationCancelTitle(language: language),
                    role: .cancel
                ) {}
                Button(
                    PetUsageBadgePermissionPresentation
                        .repairConfirmationActionTitle(language: language),
                    role: .destructive
                ) {
                    Task {
                        await permissionController.repairPermission()
                    }
                }
            } message: {
                Text(
                    PetUsageBadgePermissionPresentation
                        .repairConfirmationMessage(language: language)
                )
            }
        }
    }

    private var showsRepairAction: Bool {
        PetUsageBadgePermissionPresentation.showsRepairAction(
            for: permissionController.status
        )
    }

    private var message: String? {
        PetUsageBadgePermissionPresentation.message(
            for: permissionController.status,
            language: language
        )
    }

    private var iconName: String {
        switch permissionController.status {
        case .restartRequired:
            "arrow.clockwise.circle.fill"
        case
            .authorized,
            .permissionRequired,
            .repairRequired,
            .repairing,
            .repairFailed:
            "exclamationmark.triangle.fill"
        }
    }

    private var messageColor: Color {
        permissionController.status == .repairFailed
            ? .red : .orange
    }
}

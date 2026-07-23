import SwiftUI
import CodexMenuBarCore

struct OverviewView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.appDisplayLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                usageSection
                historySection
                sessionsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        switch store.snapshot.rateLimit {
        case .loading:
            LoadingPanel(title: text("Loading usage limits", "正在读取额度"))
        case let .content(usage):
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(usageWindows(usage).enumerated()), id: \.offset) { index, window in
                    UsageCard(
                        title: quotaTitle(index: index, count: usageWindows(usage).count),
                        window: window
                    )
                }
            }
        case let .empty(message):
            EmptyPanel(message: message)
        case let .failure(error):
            ErrorPanel(error: error)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        switch store.snapshot.history {
        case .loading:
            LoadingPanel(title: text("Loading Token history", "正在读取 Token 历史"))
        case let .content(history):
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(
                        text("60-day Token history", "60 天 Token 历史"),
                        subtitle: text("Monday–Sunday · Select a day for details", "周一至周日 · 选择日期查看详情")
                    )
                    HeatmapGrid(history: history, compact: true) { date in
                        store.showHistory(date: date)
                    }
                }
            }
        case let .empty(message):
            EmptyPanel(message: message)
        case let .failure(error):
            ErrorPanel(error: error)
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        switch store.snapshot.sessions {
        case .loading:
            LoadingPanel(title: text("Scanning interactive TUI sessions", "正在扫描交互式终端任务"))
        case let .content(sessions):
            Panel {
                VStack(alignment: .leading, spacing: 9) {
                    SectionTitle(
                        text("Live sessions", "当前任务"),
                        subtitle: text("Strict interactive TUI processes only", "仅显示交互式终端进程")
                    )
                    ForEach(sessions.prefix(4)) { session in
                        Button {
                            store.showLiveSession(pid: session.pid)
                        } label: {
                            SessionRow(
                                title: session.displayTaskDescription,
                                subtitle: "PID \(session.pid) · \(activityText(session.activity))",
                                activity: session.activity,
                                tokens: session.tokenCounts.total
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case let .empty(message):
            EmptyPanel(message: message)
        case let .failure(error):
            ErrorPanel(error: error)
        }
    }

    private func activityText(_ activity: SessionActivity) -> String {
        activity == .running ? text("Running", "运行中") : text("Stalled", "已暂停")
    }

    private func usageWindows(_ usage: UsageSnapshot) -> [WindowUsage] {
        [usage.primary, usage.secondary].compactMap { $0 }
    }

    private func quotaTitle(index: Int, count: Int) -> String {
        guard count > 1 else { return text("Usage limit", "额度") }
        return index == 0
            ? text("Primary", "短周期额度")
            : text("Secondary", "长周期额度")
    }

    private func text(_ english: String, _ chinese: String) -> String {
        appText(english, chinese, language: language)
    }
}

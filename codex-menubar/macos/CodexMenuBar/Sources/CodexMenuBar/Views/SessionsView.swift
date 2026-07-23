import SwiftUI
import CodexMenuBarCore

struct SessionsView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.appDisplayLanguage) private var language

    var body: some View {
        Group {
            switch store.snapshot.sessions {
            case .loading:
                LoadingPanel(title: text("Scanning interactive TUI sessions", "正在扫描交互式终端任务")).padding(16)
            case let .empty(message):
                EmptyPanel(message: message).padding(16)
            case let .failure(error):
                ErrorPanel(error: error).padding(16)
            case let .content(sessions):
                sessionContent(sessions)
            }
        }
    }

    private func sessionContent(_ sessions: [SessionDisplaySnapshot]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(
                        text("Interactive TUI", "交互式终端"),
                        subtitle: sessionCountText(sessions.count)
                    )
                    ForEach(sessions) { session in
                        Button {
                            store.showLiveSession(pid: session.pid)
                        } label: {
                            SessionRow(
                                title: session.displayTaskDescription,
                                subtitle: "PID \(session.pid) · \(activityText(session.activity))",
                                activity: session.activity,
                                tokens: session.tokenCounts.total
                            )
                            .padding(9)
                            .background(
                                store.selectedSessionPID == session.pid ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 270)
            Divider()
            detail(sessions)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func detail(_ sessions: [SessionDisplaySnapshot]) -> some View {
        let selected = sessions.first(where: { $0.pid == store.selectedSessionPID }) ?? sessions.first
        if let selected {
            ScrollView {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            activityText(selected.activity),
                            systemImage: selected.activity == .running ? "play.circle.fill" : "pause.circle"
                        )
                        .foregroundStyle(selected.activity == .running ? Color.green : Color.secondary)
                        SectionTitle(selected.taskDescription, subtitle: "PID \(selected.pid)")
                        TokenBreakdown(counts: selected.tokenCounts)
                        Divider()
                        Text(selected.workingDirectory)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            store.showLiveSession(pid: selected.pid)
                            store.copySelectedSessionPath()
                        } label: {
                            Label(text("Copy Path", "复制路径"), systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    private func sessionCountText(_ count: Int) -> String {
        if language == .simplifiedChinese {
            return "\(count) 个当前任务"
        }
        return "\(count) live \(count == 1 ? "session" : "sessions")"
    }

    private func activityText(_ activity: SessionActivity) -> String {
        activity == .running ? text("Running", "运行中") : text("Stalled", "已暂停")
    }

    private func text(_ english: String, _ chinese: String) -> String {
        appText(english, chinese, language: language)
    }
}

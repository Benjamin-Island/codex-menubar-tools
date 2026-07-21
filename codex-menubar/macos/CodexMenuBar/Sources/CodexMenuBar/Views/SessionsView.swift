import SwiftUI
import CodexMenuBarCore

struct SessionsView: View {
    @ObservedObject var store: DashboardStore

    var body: some View {
        Group {
            switch store.snapshot.sessions {
            case .loading:
                LoadingPanel(title: "Scanning interactive TUI sessions").padding(16)
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
                    SectionTitle("Interactive TUI", subtitle: "\(sessions.count) live \(sessions.count == 1 ? "session" : "sessions")")
                    ForEach(sessions) { session in
                        Button {
                            store.showLiveSession(pid: session.pid)
                        } label: {
                            SessionRow(
                                title: session.displayTaskDescription,
                                subtitle: "PID \(session.pid) · \(session.activity.rawValue.capitalized)",
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
                            selected.activity == .running ? "Running" : "Stalled",
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
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }
}

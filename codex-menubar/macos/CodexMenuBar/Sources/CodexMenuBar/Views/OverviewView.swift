import SwiftUI
import CodexMenuBarCore

struct OverviewView: View {
    @ObservedObject var store: DashboardStore

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
            LoadingPanel(title: "Loading usage limits")
        case let .content(usage):
            HStack(alignment: .top, spacing: 12) {
                UsageCard(title: "Primary", window: usage.primary)
                UsageCard(title: "Secondary", window: usage.secondary)
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
            LoadingPanel(title: "Loading Token history")
        case let .content(history):
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("30-week Token history", subtitle: "Monday–Sunday · Select a day for details")
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
            LoadingPanel(title: "Scanning interactive TUI sessions")
        case let .content(sessions):
            Panel {
                VStack(alignment: .leading, spacing: 9) {
                    SectionTitle("Live sessions", subtitle: "Strict interactive TUI processes only")
                    ForEach(sessions.prefix(4)) { session in
                        Button {
                            store.showLiveSession(pid: session.pid)
                        } label: {
                            SessionRow(
                                title: session.displayTaskDescription,
                                subtitle: "PID \(session.pid) · \(session.activity.rawValue.capitalized)",
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
}

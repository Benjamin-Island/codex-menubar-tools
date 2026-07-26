import SwiftUI
import CodexMenuBarCore

struct HistoryView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.appDisplayLanguage) private var language

    var body: some View {
        Group {
            switch store.snapshot.history {
            case .loading:
                LoadingPanel(title: text("Loading Token history", "正在读取 Token 历史")).padding(16)
            case let .empty(message):
                EmptyPanel(message: message).padding(16)
            case let .failure(error):
                ErrorPanel(error: error).padding(16)
            case let .content(history):
                content(history)
            }
        }
    }

    private func content(_ history: TokenHistorySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(
                            text("Token history", "Token 历史"),
                            subtitle: text("30 days · Monday–Sunday · Local time", "30 天 · 周一至周日 · 本地时间")
                        )
                        HeatmapGrid(history: history) { date in store.showDay(date) }
                        HStack(spacing: 12) {
                            Text(text("Less", "较少")).font(.caption).foregroundStyle(.secondary)
                            ForEach(0..<5) { level in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(level == 0 ? Color.secondary.opacity(0.14) : Color.green.opacity(0.18 + Double(level) * 0.19))
                                    .frame(width: 10, height: 10)
                            }
                            Text(text("More", "较多")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                detail(history)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func detail(_ history: TokenHistorySnapshot) -> some View {
        switch store.historySelection {
        case let .day(date):
            if let day = history.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(
                            day.date.formatted(date: .complete, time: .omitted),
                            subtitle: text("Daily Token breakdown", "当日 Token 明细")
                        )
                        TokenBreakdown(counts: day.counts)
                        if !day.sessions.isEmpty {
                            Divider()
                            Text(text("Sessions", "任务")).font(.subheadline.weight(.semibold))
                            ForEach(day.sessions) { session in
                                Button {
                                    store.showHistoricalSession(date: day.date, sessionID: session.id)
                                } label: {
                                    SessionRow(
                                        title: session.session.displayName,
                                        subtitle: session.session.sourceKind,
                                        activity: nil,
                                        tokens: session.counts.total
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        case let .session(date, sessionID):
            if let day = history.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
               let session = day.sessions.first(where: { $0.id == sessionID })
            {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            store.showDay(day.date)
                        } label: {
                            Label(text("Back to Day", "返回日期"), systemImage: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        SectionTitle(session.session.displayName, subtitle: "\(day.date.formatted(date: .abbreviated, time: .omitted)) · \(session.session.sourceKind)")
                        TokenBreakdown(counts: session.counts)
                        if let path = session.session.workingDirectory {
                            Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func text(_ english: String, _ chinese: String) -> String {
        appText(english, chinese, language: language)
    }
}

import AppKit
import SwiftUI
import CodexMenuBarCore

struct DashboardView: View {
    @ObservedObject var store: DashboardStore

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
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Codex Menu Bar", systemImage: "terminal.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Updated \(store.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Dashboard section", selection: $store.selectedTab) {
                Text("Overview").tag(DashboardTab.overview)
                Text("History").tag(DashboardTab.history)
                Text("Sessions \(sessionCount)").tag(DashboardTab.sessions)
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
                Label(store.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            Spacer()
            Label("Local logs · Read-only", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

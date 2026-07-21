import Combine
import CodexMenuBarCore
import Foundation

typealias DashboardReadOperation = @Sendable () async -> DashboardSnapshot

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot
    @Published var selectedTab: DashboardTab = .overview
    @Published var historySelection: HistorySelection
    @Published var selectedSessionPID: Int32?
    @Published private(set) var isRefreshing = false

    private let reader: DashboardReadOperation
    private let pasteboard: any PasteboardWriting
    private var refreshTask: Task<Void, Never>?
    private var needsRefresh = false

    init(
        snapshot: DashboardSnapshot,
        reader: @escaping DashboardReadOperation,
        pasteboard: any PasteboardWriting = SystemPasteboard()
    ) {
        self.snapshot = snapshot
        self.reader = reader
        self.pasteboard = pasteboard
        if case let .content(history) = snapshot.history {
            historySelection = .day(history.selectedDefaultDate)
        } else {
            historySelection = .day(snapshot.updatedAt)
        }
    }

    func showHistory(date: Date) {
        historySelection = .day(date)
        selectedTab = .history
    }

    func showHistoricalSession(date: Date, sessionID: String) {
        historySelection = .session(date: date, sessionID: sessionID)
        selectedTab = .history
    }

    func showDay(_ date: Date) {
        historySelection = .day(date)
    }

    func showLiveSession(pid: Int32) {
        selectedSessionPID = pid
        selectedTab = .sessions
    }

    func copySelectedSessionPath() {
        guard let selectedSessionPID,
              case let .content(sessions) = snapshot.sessions,
              let session = sessions.first(where: { $0.pid == selectedSessionPID })
        else {
            return
        }
        pasteboard.write(session.workingDirectory)
    }

    func refresh() {
        guard refreshTask == nil else {
            needsRefresh = true
            return
        }
        beginRefresh()
    }

    private func beginRefresh() {
        isRefreshing = true
        let reader = reader
        refreshTask = Task { [weak self] in
            let nextSnapshot = await reader()
            guard let self else { return }
            self.finishRefresh(with: nextSnapshot)
        }
    }

    private func finishRefresh(with nextSnapshot: DashboardSnapshot) {
        snapshot = nextSnapshot
        refreshTask = nil
        if needsRefresh {
            needsRefresh = false
            beginRefresh()
        } else {
            isRefreshing = false
        }
    }
}

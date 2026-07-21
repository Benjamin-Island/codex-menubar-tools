import Foundation

public protocol DashboardReading: Sendable {
    func read() -> DashboardSnapshot
}

public final class DashboardReader: DashboardReading, @unchecked Sendable {
    private let logIndex: CodexLogIndex
    private let historyAggregator: TokenHistoryAggregator
    private let rateLimitReducer: RateLimitReducer
    private let sessionInventory: SessionInventory
    private let sessionsDirectory: URL
    private let sessionIndexURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        logIndex: CodexLogIndex,
        historyAggregator: TokenHistoryAggregator,
        rateLimitReducer: RateLimitReducer,
        sessionInventory: SessionInventory,
        sessionsDirectory: URL,
        sessionIndexURL: URL,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.logIndex = logIndex
        self.historyAggregator = historyAggregator
        self.rateLimitReducer = rateLimitReducer
        self.sessionInventory = sessionInventory
        self.sessionsDirectory = sessionsDirectory
        self.sessionIndexURL = sessionIndexURL
        self.calendar = calendar
        self.now = now
    }

    public func read() -> DashboardSnapshot {
        let readAt = now()
        let processResult: Result<[ProcessSnapshot], Error>
        do {
            processResult = .success(try sessionInventory.scanProcesses())
        } catch {
            processResult = .failure(error)
        }

        let candidates = (try? processResult.get()) ?? []
        let requiredPaths = sessionInventory.requiredLogPaths(for: candidates)
        let modifiedSince = historyStart(now: readAt)

        let indexSnapshot: LogIndexSnapshot
        do {
            indexSnapshot = try logIndex.refresh(
                sessionsDirectory: sessionsDirectory,
                sessionIndexURL: sessionIndexURL,
                modifiedSince: modifiedSince,
                requiredPaths: requiredPaths
            )
        } catch {
            let indexError = DashboardError(
                message: "Unable to read Codex session logs",
                detail: error.localizedDescription
            )
            return DashboardSnapshot(
                rateLimit: .failure(indexError),
                history: .failure(indexError),
                sessions: sessionState(processResult: processResult, logs: [], now: readAt),
                warnings: [],
                updatedAt: readAt
            )
        }

        let history = historyAggregator.makeHistory(
            logs: indexSnapshot.logs,
            calendar: calendar,
            now: readAt
        )
        let historyState: ContentState<TokenHistorySnapshot> = history.days.contains {
            $0.counts.total > 0
        } ? .content(history) : .empty("No Token history found yet.")

        let rateLimitState: ContentState<UsageSnapshot>
        switch rateLimitReducer.reduce(logs: indexSnapshot.logs) {
        case let .snapshot(snapshot):
            rateLimitState = .content(snapshot)
        case let .failure(error):
            rateLimitState = error.menuValue == "!"
                ? .failure(DashboardError(message: error.message, detail: error.detail))
                : .empty(error.message)
        }

        return DashboardSnapshot(
            rateLimit: rateLimitState,
            history: historyState,
            sessions: sessionState(
                processResult: processResult,
                logs: indexSnapshot.logs,
                now: readAt
            ),
            warnings: indexSnapshot.warnings.map {
                DashboardWarning(path: $0.path, line: $0.line, message: $0.message)
            },
            updatedAt: readAt
        )
    }

    private func sessionState(
        processResult: Result<[ProcessSnapshot], Error>,
        logs: [IndexedSessionLog],
        now: Date
    ) -> ContentState<[SessionDisplaySnapshot]> {
        let candidates: [ProcessSnapshot]
        do {
            candidates = try processResult.get()
        } catch {
            return .failure(DashboardError(
                message: "Unable to scan Codex CLI processes",
                detail: error.localizedDescription
            ))
        }
        switch sessionInventory.read(logs: logs, candidates: candidates, now: now) {
        case let .snapshots(items):
            return items.isEmpty
                ? .empty("No interactive Codex TUI sessions are running.")
                : .content(items)
        case let .failure(error):
            return .failure(DashboardError(message: error.message, detail: error.detail))
        }
    }

    private func historyStart(now: Date) -> Date {
        var localCalendar = calendar
        localCalendar.firstWeekday = 2
        let today = localCalendar.startOfDay(for: now)
        guard let week = localCalendar.dateInterval(of: .weekOfYear, for: today),
              let start = localCalendar.date(byAdding: .weekOfYear, value: -29, to: week.start)
        else {
            return now.addingTimeInterval(-30 * 7 * 24 * 60 * 60)
        }
        return start
    }
}

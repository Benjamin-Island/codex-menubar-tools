import Foundation

public protocol DashboardReading: Sendable {
    func read() -> DashboardSnapshot
}

public final class DashboardReader: DashboardReading, @unchecked Sendable {
    private let logIndex: any IncrementalLogIndexing
    private let historyAggregator: TokenHistoryAggregator
    private let rateLimitReducer: RateLimitReducer
    private let sessionInventory: SessionInventory
    private let sessionsDirectory: URL
    private let sessionIndexURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        logIndex: any IncrementalLogIndexing,
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

        let indexSnapshot: IncrementalLogIndexSnapshot
        do {
            indexSnapshot = try logIndex.refresh(
                sessionsDirectory: sessionsDirectory,
                modifiedSince: modifiedSince,
                requiredPaths: requiredPaths,
                calendar: calendar,
                now: readAt,
                sessionIndexURL: sessionIndexURL
            )
        } catch {
            let indexError = DashboardError(
                message: "Unable to read Codex session logs",
                detail: error.localizedDescription
            )
            return DashboardSnapshot(
                rateLimit: .failure(indexError),
                history: .failure(indexError),
                sessions: sessionState(processResult: processResult, summaries: [], now: readAt),
                warnings: [],
                updatedAt: readAt
            )
        }

        let history = historyAggregator.makeHistory(
            summaries: indexSnapshot.summaries,
            calendar: calendar,
            now: readAt
        )
        let historyState: ContentState<TokenHistorySnapshot> = history.days.contains {
            $0.counts.total > 0
        } ? .content(history) : .empty("No Token history found yet.")

        let rateLimitState: ContentState<UsageSnapshot>
        switch rateLimitReducer.reduce(
            summaries: indexSnapshot.summaries,
            calendar: calendar,
            now: readAt
        ) {
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
                summaries: indexSnapshot.summaries,
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
        summaries: [SessionLogSummary],
        now: Date
    ) -> ContentState<[SessionDisplaySnapshot]> {
        let candidates: [ProcessSnapshot]
        do {
            candidates = try processResult.get()
        } catch {
            return .failure(DashboardError(
                message: "Unable to scan Codex processes",
                detail: error.localizedDescription
            ))
        }
        switch sessionInventory.read(summaries: summaries, candidates: candidates, now: now) {
        case let .snapshots(items):
            return items.isEmpty
                ? .empty("No live Codex sessions are running.")
                : .content(items)
        case let .failure(error):
            return .failure(DashboardError(message: error.message, detail: error.detail))
        }
    }

    private func historyStart(now: Date) -> Date {
        HistoryWindow.start(calendar: calendar, now: now)
    }
}

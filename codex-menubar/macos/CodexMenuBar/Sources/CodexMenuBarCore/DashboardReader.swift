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
        switch rateLimitReducer.reduce(summaries: indexSnapshot.summaries) {
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
        let desktopItems = recentDesktopSessions(summaries: summaries, now: now)
        let candidates: [ProcessSnapshot]
        do {
            candidates = try processResult.get()
        } catch {
            if !desktopItems.isEmpty {
                return .content(desktopItems)
            }
            return .failure(DashboardError(
                message: "Unable to scan Codex CLI processes",
                detail: error.localizedDescription
            ))
        }
        switch sessionInventory.read(summaries: summaries, candidates: candidates, now: now) {
        case let .snapshots(items):
            let existingSessionIDs = Set(items.compactMap(\.sessionID))
            let combined = items + desktopItems.filter {
                guard let sessionID = $0.sessionID else { return true }
                return !existingSessionIDs.contains(sessionID)
            }
            return combined.isEmpty
                ? .empty("No active Codex sessions are running.")
                : .content(combined)
        case let .failure(error):
            if !desktopItems.isEmpty {
                return .content(desktopItems)
            }
            return .failure(DashboardError(message: error.message, detail: error.detail))
        }
    }

    private func recentDesktopSessions(
        summaries: [SessionLogSummary],
        now: Date
    ) -> [SessionDisplaySnapshot] {
        let recentWindow: TimeInterval = 30 * 60
        let runningWindow: TimeInterval = 10 * 60
        let recent = summaries.filter { summary in
                let age = now.timeIntervalSince(summary.modifiedAt)
                return summary.session.sourceKind == "App"
                    && age >= -60
                    && age <= recentWindow
            }
        var newestBySessionID: [String: SessionLogSummary] = [:]
        for summary in recent {
            let existing = newestBySessionID[summary.session.id]
            if existing == nil || summary.modifiedAt > existing!.modifiedAt {
                newestBySessionID[summary.session.id] = summary
            }
        }
        return newestBySessionID.values
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(12)
            .map { summary in
                let age = now.timeIntervalSince(summary.modifiedAt)
                let isRunning = summary.lifecycle == .active && age <= runningWindow
                return SessionDisplaySnapshot(
                    pid: syntheticPID(for: summary.session.id),
                    sessionID: summary.session.id,
                    activity: isRunning ? .running : .stalled,
                    taskDescription: summary.session.name,
                    displayTaskDescription: summary.session.displayName,
                    workingDirectory: summary.session.workingDirectory ?? "",
                    sourcePath: summary.path,
                    lastUpdatedAt: summary.modifiedAt,
                    tokenCounts: summary.latestTokenCounts
                )
            }
    }

    private func syntheticPID(for sessionID: String) -> Int32 {
        var hash: UInt32 = 2_166_136_261
        for byte in sessionID.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        let positive = max(1, Int32(hash & 0x7fff_ffff))
        return -positive
    }

    private func historyStart(now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -59, to: today)
            ?? now.addingTimeInterval(-59 * 86_400)
    }
}

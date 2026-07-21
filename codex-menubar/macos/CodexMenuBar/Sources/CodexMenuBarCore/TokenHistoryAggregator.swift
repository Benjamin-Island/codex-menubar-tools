import Foundation

public struct TokenHistoryAggregator: Sendable {
    public init() {}

    public func makeHistory(
        logs: [IndexedSessionLog],
        calendar inputCalendar: Calendar,
        now: Date
    ) -> TokenHistorySnapshot {
        var calendar = inputCalendar
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -59, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let interval = DateInterval(start: start, end: end)

        var sessionByID: [String: SessionIdentity] = [:]
        var countsByDayAndSession: [Date: [String: TokenCounts]] = [:]

        for log in logs {
            sessionByID[log.session.id] = log.session
            var previous: TokenCounts?
            for event in log.tokenEvents.sorted(by: eventOrder) {
                let increment = event.cumulative.increment(since: previous)
                previous = event.cumulative
                let day = calendar.startOfDay(for: event.timestamp)
                guard day >= interval.start, day < interval.end else { continue }
                let old = countsByDayAndSession[day, default: [:]][log.session.id, default: .zero]
                countsByDayAndSession[day, default: [:]][log.session.id] = old + increment
            }
        }

        var rawDays: [(date: Date, counts: TokenCounts, sessions: [SessionDayUsage], isFuture: Bool)] = []
        for offset in 0..<60 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let sessionCounts = countsByDayAndSession[date, default: [:]]
            let sessions = sessionCounts.compactMap { sessionID, counts -> SessionDayUsage? in
                guard let session = sessionByID[sessionID] else { return nil }
                return SessionDayUsage(id: sessionID, session: session, counts: counts)
            }.sorted(by: sessionOrder)
            let total = sessions.reduce(TokenCounts.zero) { $0 + $1.counts }
            rawDays.append((date, total, sessions, false))
        }

        let thresholds = quartileThresholds(
            rawDays.lazy
                .filter { !$0.isFuture && $0.counts.total > 0 }
                .map(\.counts.total)
        )
        let days = rawDays.map { day in
            DailyUsage(
                date: day.date,
                counts: day.counts,
                sessions: day.sessions,
                heatLevel: heatLevel(total: day.counts.total, thresholds: thresholds, isFuture: day.isFuture),
                isFuture: day.isFuture
            )
        }
        let usageByDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        let displayStart = calendar.dateInterval(of: .weekOfYear, for: start)!.start
        let displayEnd = calendar.dateInterval(of: .weekOfYear, for: today)!.end
        var heatmapDays: [HeatmapDay] = []
        var displayDate = displayStart
        while displayDate < displayEnd {
            heatmapDays.append(HeatmapDay(date: displayDate, usage: usageByDate[displayDate]))
            displayDate = calendar.date(byAdding: .day, value: 1, to: displayDate)!
        }

        return TokenHistorySnapshot(
            interval: interval,
            days: days,
            heatmapDays: heatmapDays,
            selectedDefaultDate: today
        )
    }

    private func eventOrder(_ lhs: TokenEvent, _ rhs: TokenEvent) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.sequence < rhs.sequence
    }

    private func sessionOrder(_ lhs: SessionDayUsage, _ rhs: SessionDayUsage) -> Bool {
        if lhs.counts.total != rhs.counts.total { return lhs.counts.total > rhs.counts.total }
        let comparison = lhs.session.name.localizedCaseInsensitiveCompare(rhs.session.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func quartileThresholds<S: Sequence>(_ values: S) -> [Int64] where S.Element == Int64 {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [] }
        func percentile(_ fraction: Double) -> Int64 {
            let index = Int((Double(sorted.count - 1) * fraction).rounded(.down))
            return sorted[index]
        }
        return [percentile(0.25), percentile(0.50), percentile(0.75)]
    }

    private func heatLevel(total: Int64, thresholds: [Int64], isFuture: Bool) -> Int {
        guard !isFuture, total > 0, thresholds.count == 3 else { return 0 }
        if total <= thresholds[0] { return 1 }
        if total <= thresholds[1] { return 2 }
        if total <= thresholds[2] { return 3 }
        return 4
    }
}

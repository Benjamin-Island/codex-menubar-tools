import Foundation

enum HistoryWindow {
    static let dayCount = 30
    static let startDayOffset = -(dayCount - 1)

    static func start(calendar: Calendar, now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: startDayOffset, to: today)
            ?? now.addingTimeInterval(TimeInterval(startDayOffset) * 86_400)
    }
}

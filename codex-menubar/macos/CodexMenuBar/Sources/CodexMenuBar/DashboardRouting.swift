import Foundation

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case history
    case sessions

    var id: String { rawValue }
}

enum HistorySelection: Equatable {
    case day(Date)
    case session(date: Date, sessionID: String)
}

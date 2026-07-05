import Foundation

public struct WindowUsage: Equatable, Sendable {
    public let label: String
    public let usedPercent: Double?
    public let remainingPercent: Int?
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double?, remainingPercent: Int?, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let primary: WindowUsage?
    public let secondary: WindowUsage?
    public let planType: String?
    public let creditsDescription: String?
    public let reportedAt: Date?
    public let sourcePath: String

    public init(
        primary: WindowUsage?,
        secondary: WindowUsage?,
        planType: String?,
        creditsDescription: String?,
        reportedAt: Date?,
        sourcePath: String
    ) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.creditsDescription = creditsDescription
        self.reportedAt = reportedAt
        self.sourcePath = sourcePath
    }
}

public struct UsageReadError: Error, Equatable, Sendable {
    public let menuValue: String
    public let message: String
    public let detail: String?

    public init(menuValue: String, message: String, detail: String?) {
        self.menuValue = menuValue
        self.message = message
        self.detail = detail
    }
}

public enum UsageReadResult: Equatable, Sendable {
    case snapshot(UsageSnapshot)
    case failure(UsageReadError)
}

public enum UsageFormatting {
    public static func remainingFromUsed(_ usedPercent: Double?) -> Int? {
        guard let usedPercent else { return nil }
        let remaining = 100.0 - usedPercent
        return Int(min(100.0, max(0.0, remaining)).rounded())
    }

    public static func windowLabel(minutes: Double?) -> String {
        guard let minutes else { return "--" }
        let wholeMinutes = Int(minutes)
        if wholeMinutes % 1440 == 0 {
            return "\(wholeMinutes / 1440)d"
        }
        if wholeMinutes % 60 == 0 {
            return "\(wholeMinutes / 60)h"
        }
        return "\(wholeMinutes)m"
    }

    public static func menuLabel(_ remainingPercent: Int?) -> String {
        guard let remainingPercent else { return "--" }
        return "\(min(100, max(0, remainingPercent)))"
    }

    public static func percentLabel(_ remainingPercent: Int?) -> String {
        guard let remainingPercent else { return "--" }
        return "\(remainingPercent)%"
    }

    public static func dateLabel(_ date: Date?, calendar: Calendar = .current, now: Date = Date()) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm:ss"
        } else {
            formatter.dateFormat = "MMM d HH:mm"
        }
        return formatter.string(from: date)
    }
}

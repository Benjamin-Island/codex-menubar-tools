import Foundation

struct StatusItemPresentation: Equatable {
    let usageLabel: String
    let progress: Double?
    let sessionLabel: String
    let accessibilityValue: String

    static func make(
        remainingPercent: Int?,
        sessionCount: Int,
        hasUsageError: Bool = false
    ) -> StatusItemPresentation {
        let safeSessions = max(0, sessionCount)
        let usageLabel: String
        let progress: Double?
        let usageDescription: String
        if hasUsageError {
            usageLabel = "!"
            progress = nil
            usageDescription = "Usage error"
        } else if let remainingPercent {
            let clamped = min(100, max(0, remainingPercent))
            usageLabel = "\(clamped)"
            progress = Double(clamped) / 100
            usageDescription = "\(clamped) percent remaining"
        } else {
            usageLabel = "--"
            progress = nil
            usageDescription = "Usage unavailable"
        }
        let noun = safeSessions == 1 ? "interactive session" : "interactive sessions"
        return StatusItemPresentation(
            usageLabel: usageLabel,
            progress: progress,
            sessionLabel: "\(safeSessions)",
            accessibilityValue: "\(usageDescription), \(safeSessions) \(noun)"
        )
    }
}

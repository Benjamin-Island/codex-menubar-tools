import SwiftUI
import CodexMenuBarCore

enum PetUsageBadgeTone: Equatable {
    case neutral
    case green
    case orange
    case red

    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .green:
            .green
        case .orange:
            .orange
        case .red:
            .red
        }
    }
}

struct PetUsageBadgePresentation: Equatable {
    let projectTitle: String
    let primaryText: String
    let secondaryText: String
    let runningText: String
    let primaryRemainingPercent: Int?
    let primaryTone: PetUsageBadgeTone

    static func make(
        snapshot: DashboardSnapshot,
        language: AppDisplayLanguage
    ) -> PetUsageBadgePresentation {
        let usage: UsageSnapshot?
        if case let .content(value) = snapshot.rateLimit {
            usage = value
        } else {
            usage = nil
        }

        let sessions: [SessionDisplaySnapshot]
        if case let .content(value) = snapshot.sessions {
            sessions = value
        } else {
            sessions = []
        }
        let running = sessions.filter { $0.activity == .running }
        let projectTitle = running.first?.displayTaskDescription
            ?? sessions.first?.displayTaskDescription
            ?? appText(
                "No active Codex tasks",
                "当前没有 Codex 任务",
                language: language
            )
        let runningText: String
        if language == .simplifiedChinese {
            runningText = "\(running.count) 个运行中"
        } else {
            let noun = running.count == 1 ? "task" : "tasks"
            runningText = "\(running.count) \(noun) running"
        }
        let primaryRemaining = usage?.primary?.remainingPercent
        return PetUsageBadgePresentation(
            projectTitle: projectTitle,
            primaryText: UsageFormatting.percentLabel(primaryRemaining),
            secondaryText: UsageFormatting.percentLabel(
                usage?.secondary?.remainingPercent
            ),
            runningText: runningText,
            primaryRemainingPercent: primaryRemaining,
            primaryTone: tone(for: primaryRemaining)
        )
    }

    static func tone(for remainingPercent: Int?) -> PetUsageBadgeTone {
        guard let remainingPercent else { return .neutral }
        if remainingPercent <= 10 { return .red }
        if remainingPercent <= 30 { return .orange }
        return .green
    }
}

struct PetUsageBadgeView: View {
    @ObservedObject var store: DashboardStore
    let language: AppDisplayLanguage
    let onClick: () -> Void

    private var presentation: PetUsageBadgePresentation {
        .make(snapshot: store.snapshot, language: language)
    }

    var body: some View {
        Button(action: onClick) {
            Text(presentation.primaryText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(presentation.primaryTone.color)
                .frame(
                    width: PetUsageBadgePlacement.badgeSize.width,
                    height: PetUsageBadgePlacement.badgeSize.height
                )
                .background(
                    .regularMaterial,
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .frame(
            width: PetUsageBadgePlacement.badgeSize.width,
            height: PetUsageBadgePlacement.badgeSize.height
        )
        .accessibilityLabel(
            accessibilityLabel(
                remaining: presentation.primaryRemainingPercent
            )
        )
    }

    private func accessibilityLabel(remaining: Int?) -> String {
        guard let remaining else {
            return appText(
                "Primary remaining unavailable",
                "Primary 剩余额度不可用",
                language: language
            )
        }
        return appText(
            "Primary remaining \(remaining) percent",
            "Primary 剩余 \(remaining)%",
            language: language
        )
    }
}

struct PetUsageSummaryView: View {
    @ObservedObject var store: DashboardStore
    let language: AppDisplayLanguage

    private var presentation: PetUsageBadgePresentation {
        .make(snapshot: store.snapshot, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(presentation.projectTitle)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 10) {
                metric(
                    title: "Primary",
                    value: presentation.primaryText,
                    tone: presentation.primaryTone
                )
                metric(
                    title: "Secondary",
                    value: presentation.secondaryText,
                    tone: .neutral
                )
                Label(
                    presentation.runningText,
                    systemImage: "bolt.fill"
                )
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 14)
        .frame(
            width: PetUsageBadgePlacement.summarySize.width,
            height: PetUsageBadgePlacement.summarySize.height,
            alignment: .leading
        )
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 13, y: 5)
        .accessibilityElement(children: .combine)
    }

    private func metric(
        title: String,
        value: String,
        tone: PetUsageBadgeTone
    ) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tone.color)
        }
    }
}

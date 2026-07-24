import SwiftUI
import CodexMenuBarCore

struct PetIslandView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var preferences: PetIslandPreferences
    let isExpanded: Bool
    let isPeeking: Bool
    let dockEdge: PetDockEdge?
    let initialDirection: PetDockEdge
    let toggleExpanded: () -> Void
    let beginDrag: () -> Void
    let changeDirection: (PetDockEdge) -> Void
    let updateDrag: (CGSize) -> Void
    let endDrag: (CGSize) -> Void
    let openDashboard: () -> Void
    @Environment(\.appDisplayLanguage) private var language
    @State private var dragDirection: PetDockEdge = .right
    @State private var isDraggingPet = false

    private var usage: UsageSnapshot? {
        guard case let .content(usage) = store.snapshot.rateLimit else { return nil }
        return usage
    }

    private var sessions: [SessionDisplaySnapshot] {
        guard case let .content(sessions) = store.snapshot.sessions else { return [] }
        return sessions
    }

    private var runningSessions: [SessionDisplaySnapshot] {
        sessions.filter { $0.activity == .running }
    }

    private var usageWindows: [WindowUsage] {
        guard let usage else { return [] }
        return [usage.primary, usage.secondary].compactMap { $0 }
    }

    private var preferredUsage: WindowUsage? {
        usage?.secondary ?? usage?.primary
    }

    var body: some View {
        floatingSurface
        .frame(
            width: PetIslandPlacement.size(expanded: isExpanded, peeking: isPeeking).width,
            height: PetIslandPlacement.size(expanded: isExpanded, peeking: isPeeking).height
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text("Codex Pet Status", "Codex 宠物状态"))
        .onAppear {
            dragDirection = initialDirection
        }
    }

    private var floatingSurface: some View {
        ZStack {
            if isPeeking {
                ZStack {
                    if isDraggingPet {
                        floatingPet
                    } else {
                        peekingPet
                    }
                }
                .frame(
                    width: PetIslandPlacement.peekSize.width,
                    height: PetIslandPlacement.peekSize.height
                )
                .overlay {
                    petDragCapture
                }
            } else if isExpanded {
                expandedTaskPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))

                Button(action: toggleExpanded) {
                    floatingPet
                        .frame(width: 78, height: 78)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 10)
                .help(text("Hide Codex summary", "收起 Codex 摘要"))
            } else {
                Button(action: toggleExpanded) {
                    ZStack(alignment: .bottomTrailing) {
                        if !isDraggingPet {
                            collapsedFloatingSummary
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                        }
                        floatingPet
                    }
                    .frame(
                        width: PetIslandPlacement.floatingSize.width,
                        height: PetIslandPlacement.floatingSize.height,
                        alignment: .bottomTrailing
                    )
                }
                .buttonStyle(.plain)
                .help(text("Show Codex summary", "展开 Codex 摘要"))
                .overlay(alignment: .bottomTrailing) {
                    petDragCapture
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var peekingPet: some View {
        VStack(spacing: -6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: dockedUsageProgress)
                    .stroke(
                        summaryUsageColor(dockedUsage?.remainingPercent),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                pet
                    .frame(width: 50, height: 56)
            }
            .frame(width: 82, height: 82)

            Text(dockedUsageText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                }
        }
        .padding(.top, 6)
        .padding(.horizontal, 8)
        .frame(
            width: PetIslandPlacement.peekSize.width,
            height: PetIslandPlacement.peekSize.height
        )
        .contentShape(Circle())
        .accessibilityLabel(text("Codex pet usage", "Codex 宠物额度"))
        .accessibilityValue(dockedUsageAccessibilityText)
    }

    private var collapsedFloatingSummary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(primaryTaskTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    ForEach(Array(usageWindows.enumerated()), id: \.offset) { _, window in
                        compactPercent(
                            label: window.label,
                            remaining: window.remainingPercent
                        )
                    }
                    Label(
                        runningCountText,
                        systemImage: runningSessions.isEmpty ? "pause.fill" : "bolt.fill"
                    )
                    .foregroundStyle(runningSessions.isEmpty ? Color.secondary : Color.green)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
            }

            Spacer(minLength: 4)
            usageRing(remaining: preferredUsage?.remainingPercent)
        }
        .padding(.leading, 14)
        .padding(.trailing, 11)
        .frame(width: 306, height: 66)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 13, y: 5)
    }

    private var floatingPet: some View {
        ZStack(alignment: .bottomTrailing) {
            pet
                .frame(width: 60, height: 66)
                .padding(.trailing, 8)
                .padding(.bottom, 5)

            activityBadge
                .offset(x: -2, y: -2)
        }
        .frame(width: 78, height: 78)
        .contentShape(Circle())
    }

    private var petDragCapture: some View {
        PetDragCaptureView(
            onClick: toggleExpanded,
            onDragBegan: {
                isDraggingPet = true
                beginDrag()
            },
            onDirectionChanged: { direction in
                dragDirection = direction
                changeDirection(direction)
            },
            onDragChanged: updateDrag,
            onDragEnded: { translation in
                endDrag(translation)
                isDraggingPet = false
            }
        )
        .frame(width: 78, height: 78)
        .accessibilityLabel(text("Drag Codex pet", "拖动 Codex 宠物"))
        .help(text(
            "Drag Codex pet; move to a screen edge to dock it",
            "拖动 Codex 宠物；移到屏幕边缘即可吸附"
        ))
    }

    private var expandedTaskPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(runningSessions.isEmpty ? Color.gray.opacity(0.16) : Color.green.opacity(0.16))
                    Image(systemName: runningSessions.isEmpty ? "checkmark" : "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(runningSessions.isEmpty ? Color.secondary : Color.green)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(text("Codex tasks", "Codex 任务"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(sessionSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: toggleExpanded) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help(text("Hide summary", "收起摘要"))
            }

            Divider()

            taskList

            Divider()

            HStack(spacing: 8) {
                ForEach(Array(usageWindows.enumerated()), id: \.offset) { _, window in
                    summaryMetric(
                        label: window.label,
                        value: percentText(window.remainingPercent)
                    )
                }
                summaryMetric(
                    label: text("Running", "运行中"),
                    value: "\(runningSessions.count)"
                )

                Spacer(minLength: 2)

                Button(action: openDashboard) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .help(text("Open full Codex usage dashboard", "打开完整 Codex 用量面板"))
            }
        }
        .padding(14)
        .frame(width: PetIslandPlacement.expandedSize.width, height: 326)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    @ViewBuilder
    private var taskList: some View {
        if sessions.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(text("No active Codex tasks", "当前没有 Codex 任务"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 172)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sessions) { session in
                        taskRow(session)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 3)
            }
            .scrollIndicators(.visible)
            .frame(height: 172)
        }
    }

    private func taskRow(_ session: SessionDisplaySnapshot) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        session.activity == .running
                            ? Color.green.opacity(0.16)
                            : Color.orange.opacity(0.16)
                    )
                Image(systemName: session.activity == .running ? "bolt.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(session.activity == .running ? Color.green : Color.orange)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTaskDescription)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Text(projectName(for: session))
                    Text("·")
                    Text(tokenText(session.tokenCounts.total))
                    Text("·")
                    Text(
                        session.activity == .running
                            ? text("Running", "运行中")
                            : text("Recent", "最近")
                    )
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 5)

            Image(systemName: session.activity == .running ? "arrow.triangle.2.circlepath" : "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(session.activity == .running ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.56), in: RoundedRectangle(cornerRadius: 14))
    }

    private func summaryMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .frame(width: 84, height: 42, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
    }

    private func compactPercent(label: String, remaining: Int?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(percentText(remaining))
                .foregroundStyle(summaryUsageColor(remaining))
        }
    }

    private func usageRing(remaining: Int?) -> some View {
        let clamped = min(100, max(0, remaining ?? 0))
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(clamped) / 100)
                .stroke(
                    summaryUsageColor(remaining),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(remaining.map(String.init) ?? "--")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .frame(width: 38, height: 38)
    }

    private var activityBadge: some View {
        ZStack {
            Circle()
                .fill(runningSessions.isEmpty ? Color.gray : Color.green)
            Text("\(runningSessions.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
        .overlay {
            Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private var pet: some View {
        if let selectedPet = preferences.selectedPet {
            PetSpriteView(
                pet: selectedPet,
                state: petAnimationState
            )
        } else {
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.secondary)
        }
    }

    private var petAnimationState: PetAnimationState {
        if isPeeking {
            return dockEdge == .left ? .peekingLeft : .peekingRight
        }
        guard !runningSessions.isEmpty || isDraggingPet else {
            return .idle
        }
        return dragDirection == .left ? .runningLeft : .runningRight
    }

    private var dockedUsage: WindowUsage? {
        preferredUsage
    }

    private var dockedUsageProgress: CGFloat {
        CGFloat(min(100, max(0, dockedUsage?.remainingPercent ?? 0))) / 100
    }

    private var dockedUsageText: String {
        "\(percentText(dockedUsage?.remainingPercent)) · \(resetCountdown(dockedUsage?.resetsAt))"
    }

    private var dockedUsageAccessibilityText: String {
        language == .simplifiedChinese
            ? "剩余 \(percentText(dockedUsage?.remainingPercent))，\(resetCountdown(dockedUsage?.resetsAt))后重置"
            : "\(percentText(dockedUsage?.remainingPercent)) remaining, resets in \(resetCountdown(dockedUsage?.resetsAt))"
    }

    private func resetCountdown(_ date: Date?) -> String {
        guard let date else { return "--" }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return text("now", "现在") }
        if remaining >= 86_400 {
            let value = max(1, Int(ceil(remaining / 86_400)))
            return language == .simplifiedChinese ? "\(value)天" : "\(value)d"
        }
        if remaining >= 3_600 {
            let value = max(1, Int(ceil(remaining / 3_600)))
            return language == .simplifiedChinese ? "\(value)小时" : "\(value)h"
        }
        let value = max(1, Int(ceil(remaining / 60)))
        return language == .simplifiedChinese ? "\(value)分钟" : "\(value)m"
    }

    private var sessionSummary: String {
        if runningSessions.isEmpty {
            if sessions.isEmpty {
                return text("No active sessions", "当前没有任务")
            }
            return language == .simplifiedChinese
                ? "\(sessions.count) 个最近任务"
                : "\(sessions.count) recent tasks"
        }
        if language == .simplifiedChinese {
            return "\(runningSessions.count) 个运行中 · 共 \(sessions.count) 个任务"
        }
        let noun = runningSessions.count == 1 ? "task" : "tasks"
        return "\(runningSessions.count) active \(noun) · \(sessions.count) total sessions"
    }

    private var primaryTaskTitle: String {
        runningSessions.first?.displayTaskDescription
            ?? sessions.first?.displayTaskDescription
            ?? text("No active Codex tasks", "当前没有 Codex 任务")
    }

    private func projectName(for session: SessionDisplaySnapshot) -> String {
        let name = URL(fileURLWithPath: session.workingDirectory).lastPathComponent
        return name.isEmpty ? "Codex" : name
    }

    private func tokenText(_ total: Int64) -> String {
        if total >= 1_000_000 {
            return String(
                format: language == .simplifiedChinese ? "%.1fM Token" : "%.1fM tokens",
                Double(total) / 1_000_000
            )
        }
        if total >= 1_000 {
            return String(
                format: language == .simplifiedChinese ? "%.1fK Token" : "%.1fK tokens",
                Double(total) / 1_000
            )
        }
        return language == .simplifiedChinese ? "\(total) Token" : "\(total) tokens"
    }

    private func percentText(_ remaining: Int?) -> String {
        remaining.map { "\($0)%" } ?? "--"
    }

    private func summaryUsageColor(_ remaining: Int?) -> Color {
        guard let remaining else { return .secondary }
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .green
    }

    private var runningCountText: String {
        language == .simplifiedChinese
            ? "\(runningSessions.count) 运行中"
            : "\(runningSessions.count) running"
    }

    private func text(_ english: String, _ chinese: String) -> String {
        appText(english, chinese, language: language)
    }
}

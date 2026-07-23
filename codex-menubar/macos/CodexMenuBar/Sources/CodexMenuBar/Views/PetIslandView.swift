import SwiftUI
import CodexMenuBarCore

struct PetIslandView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var preferences: PetIslandPreferences
    let mode: PetSurfaceMode
    let isExpanded: Bool
    let menuBarHeight: CGFloat
    let toggleExpanded: () -> Void
    let openDashboard: () -> Void

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

    var body: some View {
        Group {
            switch mode {
            case .notch:
                notchSurface
            case .floating:
                floatingSurface
            }
        }
        .frame(
            width: PetIslandPlacement.size(
                mode: mode,
                expanded: isExpanded,
                menuBarHeight: menuBarHeight
            ).width,
            height: PetIslandPlacement.size(
                mode: mode,
                expanded: isExpanded,
                menuBarHeight: menuBarHeight
            ).height
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex Pet Status")
    }

    private var notchSurface: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                summaryCard
                    .padding(.top, menuBarHeight + 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button(action: toggleExpanded) {
                compactNotch
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide Codex summary" : "Show Codex summary")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var compactNotch: some View {
        HStack(spacing: 0) {
            usageMetric(
                label: usage?.primary?.label ?? "5h",
                remaining: usage?.primary?.remainingPercent
            )
            .frame(width: 67, alignment: .leading)

            Spacer(minLength: 72)

            HStack(spacing: 8) {
                usageMetric(
                    label: usage?.secondary?.label ?? "7d",
                    remaining: usage?.secondary?.remainingPercent
                )
                activityDot
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(width: PetIslandPlacement.notchWidth, height: menuBarHeight)
        .foregroundStyle(.white)
        .background {
            UnevenRoundedRectangle(
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14
            )
            .fill(Color.black.opacity(0.97))
        }
        .contentShape(Rectangle())
    }

    private var floatingSurface: some View {
        ZStack {
            if isExpanded {
                summaryCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))

                Button(action: toggleExpanded) {
                    floatingPet
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 15)
                .help("Hide Codex summary")
            } else {
                Button(action: toggleExpanded) {
                    floatingPet
                }
                .buttonStyle(.plain)
                .help("Show Codex summary")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var floatingPet: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

            pet
                .frame(width: 58, height: 63)
                .offset(x: -5, y: -4)

            activityBadge
                .offset(x: -1, y: -1)
        }
        .frame(width: 68, height: 68)
        .contentShape(Circle())
    }

    private var summaryCard: some View {
        VStack(spacing: 11) {
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
                    Text(runningSessions.first?.displayTaskDescription ?? "Codex is ready")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
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
                .help("Hide summary")
            }

            Divider()

            HStack(spacing: 8) {
                summaryMetric(
                    label: usage?.primary?.label ?? "5h",
                    value: percentText(usage?.primary?.remainingPercent)
                )
                summaryMetric(
                    label: usage?.secondary?.label ?? "7d",
                    value: percentText(usage?.secondary?.remainingPercent)
                )
                summaryMetric(
                    label: "Active",
                    value: "\(runningSessions.count)"
                )

                Button(action: openDashboard) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Open full Codex usage dashboard")
            }
        }
        .padding(14)
        .frame(width: PetIslandPlacement.expandedSize.width, height: 132)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private func usageMetric(label: String, remaining: Int?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.white.opacity(0.62))
            Text(remaining.map { "\($0)%" } ?? "--")
                .foregroundStyle(usageColor(remaining))
                .contentTransition(.numericText())
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
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
        .frame(width: 82, height: 42, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
    }

    private var activityDot: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(runningSessions.isEmpty ? Color.secondary : Color.green)
                .frame(width: 6, height: 6)
            Text("\(runningSessions.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
    }

    private var activityBadge: some View {
        ZStack {
            Circle()
                .fill(runningSessions.isEmpty ? Color.gray : Color.green)
            Image(systemName: runningSessions.isEmpty ? "checkmark" : "bolt.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
        .overlay {
            Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private var pet: some View {
        if let selectedPet = preferences.selectedPet {
            PetSpriteView(
                pet: selectedPet,
                isActive: !runningSessions.isEmpty
            )
        } else {
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionSummary: String {
        if runningSessions.isEmpty {
            return sessions.isEmpty ? "No active sessions" : "\(sessions.count) sessions waiting"
        }
        let noun = runningSessions.count == 1 ? "task" : "tasks"
        return "\(runningSessions.count) active \(noun) · \(sessions.count) total sessions"
    }

    private func percentText(_ remaining: Int?) -> String {
        remaining.map { "\($0)%" } ?? "--"
    }

    private func usageColor(_ remaining: Int?) -> Color {
        guard let remaining else { return .white.opacity(0.6) }
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .green
    }
}

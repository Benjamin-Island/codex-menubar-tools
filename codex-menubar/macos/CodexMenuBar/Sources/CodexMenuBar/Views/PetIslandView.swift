import SwiftUI
import CodexMenuBarCore

struct PetIslandView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var preferences: PetIslandPreferences
    let isNotchedDisplay: Bool
    let openDashboard: () -> Void

    private var usage: UsageSnapshot? {
        guard case let .content(usage) = store.snapshot.rateLimit else { return nil }
        return usage
    }

    private var sessions: [SessionDisplaySnapshot] {
        guard case let .content(sessions) = store.snapshot.sessions else { return [] }
        return sessions
    }

    var body: some View {
        Button(action: openDashboard) {
            ZStack(alignment: .top) {
                TopDockShape()
                    .fill(Color.black.opacity(0.96))
                    .frame(width: PetIslandPlacement.panelSize.width, height: 48)
                    .overlay(alignment: .top) {
                        statusContent
                            .frame(height: 45)
                    }

                pet
                    .frame(width: 62, height: 67)
                    .offset(y: isNotchedDisplay ? 25 : 22)
            }
            .frame(
                width: PetIslandPlacement.panelSize.width,
                height: PetIslandPlacement.panelSize.height,
                alignment: .top
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Codex usage dashboard")
        .accessibilityLabel("Codex Pet Island")
        .accessibilityValue(accessibilityValue)
    }

    private var statusContent: some View {
        HStack(spacing: 0) {
            usageMetric(
                label: usage?.primary?.label ?? "5h",
                remaining: usage?.primary?.remainingPercent
            )
            .frame(width: 90, alignment: .leading)

            Color.clear
                .frame(width: 100)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                usageMetric(
                    label: usage?.secondary?.label ?? "7d",
                    remaining: usage?.secondary?.remainingPercent
                )
                Divider()
                    .frame(height: 15)
                    .overlay(Color.white.opacity(0.25))
                HStack(spacing: 4) {
                    Circle()
                        .fill(sessions.isEmpty ? Color.secondary : Color.green)
                        .frame(width: 7, height: 7)
                    Text("\(sessions.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .foregroundStyle(.white)
    }

    private func usageMetric(label: String, remaining: Int?) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.white.opacity(0.68))
            Text(remaining.map { "\($0)%" } ?? "--")
                .foregroundStyle(usageColor(remaining))
                .contentTransition(.numericText())
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    @ViewBuilder
    private var pet: some View {
        if let selectedPet = preferences.selectedPet {
            PetSpriteView(
                pet: selectedPet,
                isActive: sessions.contains(where: { $0.activity == .running })
            )
        } else {
            Image(systemName: "pawprint.fill")
                .resizable()
                .scaledToFit()
                .padding(14)
                .foregroundStyle(.white)
        }
    }

    private func usageColor(_ remaining: Int?) -> Color {
        guard let remaining else { return .white.opacity(0.6) }
        if remaining <= 10 { return .red }
        if remaining <= 30 { return .orange }
        return .green
    }

    private var accessibilityValue: String {
        let primary = usage?.primary?.remainingPercent.map { "\($0) percent remaining" }
            ?? "usage unavailable"
        let noun = sessions.count == 1 ? "session" : "sessions"
        return "\(primary), \(sessions.count) active \(noun)"
    }
}

private struct TopDockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(22, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

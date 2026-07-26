import SwiftUI
import CodexMenuBarCore

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            }
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct UsageCard: View {
    let title: String
    let window: WindowUsage?
    @Environment(\.appDisplayLanguage) private var language

    var todayInitialText: String? {
        UsageFormatting.todayInitialLabel(window)
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                    Text(title).font(.headline)
                    Spacer()
                    Text(window?.label ?? "--")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(UsageFormatting.percentLabel(window?.remainingPercent))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                ProgressView(value: Double(window?.remainingPercent ?? 0), total: 100)
                if let todayInitialText {
                    Text(todayInitialText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Text("\(appText("Resets", "重置时间", language: language)) \(UsageFormatting.dateLabel(window?.resetsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HeatmapGrid: View {
    let history: TokenHistorySnapshot
    var compact = false
    let onSelect: (Date) -> Void

    private var cell: CGFloat { compact ? 9 : 12 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(
                rows: Array(repeating: GridItem(.fixed(cell), spacing: 3), count: 7),
                spacing: 3
            ) {
                ForEach(history.heatmapDays) { displayDay in
                    if let day = displayDay.usage {
                        Button {
                            onSelect(day.date)
                        } label: {
                            RoundedRectangle(cornerRadius: compact ? 2 : 3)
                                .fill(heatColor(day.heatLevel))
                                .frame(width: cell, height: cell)
                        }
                        .buttonStyle(.plain)
                        .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(TokenPresentation.count(day.counts.total)) Tokens")
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(day.counts.total) Tokens, heat level \(day.heatLevel)")
                    } else {
                        Color.clear
                            .frame(width: cell, height: cell)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func heatColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color.green.opacity(0.25)
        case 2: return Color.green.opacity(0.45)
        case 3: return Color.green.opacity(0.68)
        case 4: return Color.green.opacity(0.95)
        default: return Color.secondary.opacity(0.14)
        }
    }
}

struct TokenBreakdown: View {
    let counts: TokenCounts
    @Environment(\.appDisplayLanguage) private var language

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            tokenRow(appText("Total", "总计", language: language), value: counts.total, icon: "sum")
            tokenRow(appText("Input", "输入", language: language), value: counts.input, icon: "arrow.down.circle")
            tokenRow(appText("Cached", "缓存", language: language), value: counts.cachedInput, icon: "bolt.horizontal.circle")
            tokenRow(appText("Output", "输出", language: language), value: counts.output, icon: "arrow.up.circle")
            tokenRow(appText("Reasoning", "推理", language: language), value: counts.reasoning, icon: "brain.head.profile")
        }
    }

    private func tokenRow(_ label: String, value: Int64, icon: String) -> some View {
        GridRow {
            Label(label, systemImage: icon).foregroundStyle(.secondary)
            Text(TokenPresentation.count(value))
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct SessionRow: View {
    let title: String
    let subtitle: String
    let activity: SessionActivity?
    let tokens: Int64

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity == .running ? "play.circle.fill" : "pause.circle")
                .foregroundStyle(activity == .running ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(TokenPresentation.compact(tokens))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct LoadingPanel: View {
    let title: String
    var body: some View {
        Panel {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(title).foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyPanel: View {
    let message: String
    @Environment(\.appDisplayLanguage) private var language
    var body: some View {
        Panel {
            Label(localizedDashboardMessage(message, language: language), systemImage: "tray")
                .foregroundStyle(.secondary)
        }
    }
}

struct ErrorPanel: View {
    let error: DashboardError
    @Environment(\.appDisplayLanguage) private var language
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 5) {
                Label(
                    localizedDashboardMessage(error.message, language: language),
                    systemImage: "exclamationmark.triangle.fill"
                )
                    .foregroundStyle(.orange)
                if let detail = error.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }
}

struct PartialWarningBanner: View {
    let count: Int
    @Environment(\.appDisplayLanguage) private var language
    var body: some View {
        Label(warningText, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    private var warningText: String {
        if language == .simplifiedChinese {
            return "\(count) 条日志警告；仍显示可用数据。"
        }
        return "\(count) log \(count == 1 ? "warning" : "warnings"); available data is still shown."
    }
}

enum TokenPresentation {
    static func count(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func compact(_ value: Int64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

import Foundation
import SwiftUI
import Charts

/// S19-06 — 安装历史可视化数据
struct InstallHistoryChartPoint: Identifiable, Sendable {
    let id: String
    let date: Date
    let label: String
    let sessions: Int
    let tools: Int
}

enum InstallHistoryAnalytics {
    enum Range: String, CaseIterable, Identifiable {
        case days7 = "7d"
        case days30 = "30d"
        case all = "all"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .days7: String(localized: "ui.InstallHistoryChartSection.fdef8c231f")
            case .days30: String(localized: "ui.InstallHistoryChartSection.923a9a444c")
            case .all: String(localized: "ui.InstallHistoryChartSection.a8b0c20416")
            }
        }

        var startDate: Date? {
            let cal = Calendar.current
            switch self {
            case .days7:
                return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))
            case .days30:
                return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date()))
            case .all:
                return nil
            }
        }
    }

    enum SourceFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case bundle = "bundle"
        case discover = "discover"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: String(localized: "ui.InstallHistoryChartSection.99b7a390f3")
            case .bundle: String(localized: "ui.InstallHistoryChartSection.05dd37e7c5")
            case .discover: String(localized: "ui.InstallHistoryChartSection.336b6e9cb7")
            }
        }
    }

    static func filtered(
        entries: [InstallHistoryEntry],
        range: Range,
        source: SourceFilter
    ) -> [InstallHistoryEntry] {
        entries.filter { entry in
            if let start = range.startDate, entry.date < start { return false }
            switch source {
            case .all: return true
            case .bundle: return entry.source == .bundle
            case .discover: return entry.source == .discover
            }
        }
    }

    static func dailyPoints(from entries: [InstallHistoryEntry]) -> [InstallHistoryChartPoint] {
        let cal = Calendar.current
        var buckets: [Date: (sessions: Int, tools: Int)] = [:]
        for entry in entries {
            let day = cal.startOfDay(for: entry.date)
            var bucket = buckets[day] ?? (0, 0)
            bucket.sessions += 1
            bucket.tools += entry.toolCount
            buckets[day] = bucket
        }
        return buckets.keys.sorted().map { day in
            let bucket = buckets[day]!
            let label = day.formatted(.dateTime.month(.abbreviated).day())
            return InstallHistoryChartPoint(
                id: "\(day.timeIntervalSince1970)",
                date: day,
                label: label,
                sessions: bucket.sessions,
                tools: bucket.tools
            )
        }
    }
}

struct InstallHistoryChartSection: View {
    let entries: [InstallHistoryEntry]
    @State private var range: InstallHistoryAnalytics.Range = .days30
    @State private var source: InstallHistoryAnalytics.SourceFilter = .all

    private var filtered: [InstallHistoryEntry] {
        InstallHistoryAnalytics.filtered(entries: entries, range: range, source: source)
    }

    private var points: [InstallHistoryChartPoint] {
        InstallHistoryAnalytics.dailyPoints(from: filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "ui.InstallHistoryChartSection.164c829870"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker(String(localized: "ui.InstallHistoryChartSection.df011658c3"), selection: $range) {
                    ForEach(InstallHistoryAnalytics.Range.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            Picker(String(localized: "ui.InstallHistoryChartSection.26ca20b161"), selection: $source) {
                ForEach(InstallHistoryAnalytics.SourceFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                Text(String(localized: "ui.InstallHistoryChartSection.eb83384231"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value(String(localized: "ui.InstallHistoryChartSection.4ff1e74e43"), point.date, unit: .day),
                        y: .value(String(localized: "ui.InstallHistoryChartSection.2f2262e4d6"), point.tools)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, points.count / 6))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 160)

                Text(String(format: String(localized: "ui.InstallHistoryChartSection.fmt.6395e83cbb"), locale: .current, "\(filtered.count)", "\(filtered.reduce(0) { $0 + $1.toolCount })"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

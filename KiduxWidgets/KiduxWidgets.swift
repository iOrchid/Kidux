import WidgetKit
import SwiftUI

@main
struct KiduxWidgets: WidgetBundle {
    var body: some Widget {
        KiduxUpdatesWidget()
        KiduxHealthWidget()
        KiduxInstallWidget()
    }
}

// MARK: - Timeline

struct KiduxWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: KiduxWidgetSnapshot
}

struct KiduxWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> KiduxWidgetEntry {
        KiduxWidgetEntry(
            date: Date(),
            snapshot: KiduxWidgetSnapshot(
                outdatedCount: 3,
                healthRaw: "yellow",
                healthDetail: "3 款可更新",
                isInstalling: false,
                installTitle: nil,
                installProgress: 0,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (KiduxWidgetEntry) -> Void) {
        completion(KiduxWidgetEntry(date: Date(), snapshot: KiduxWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KiduxWidgetEntry>) -> Void) {
        let entry = KiduxWidgetEntry(date: Date(), snapshot: KiduxWidgetSnapshotStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Updates (small)

struct KiduxUpdatesWidget: Widget {
    let kind = "KiduxUpdatesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KiduxWidgetProvider()) { entry in
            KiduxUpdatesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("可更新软件")
        .description("显示 Homebrew / MAS 可更新数量")
        .supportedFamilies([.systemSmall])
    }
}

struct KiduxUpdatesWidgetView: View {
    let entry: KiduxWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("启椟", systemImage: "shippingbox.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(entry.snapshot.outdatedCount)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(entry.snapshot.outdatedCount > 0 ? Color.orange : Color.primary)
            Text(entry.snapshot.outdatedCount > 0 ? "款可更新" : "已是最新")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
    }
}

// MARK: - Health (medium)

struct KiduxHealthWidget: Widget {
    let kind = "KiduxHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KiduxWidgetProvider()) { entry in
            KiduxHealthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("环境健康")
        .description("环境红绿灯与漂移摘要")
        .supportedFamilies([.systemMedium])
    }
}

struct KiduxHealthWidgetView: View {
    let entry: KiduxWidgetEntry

    private var healthColor: Color {
        switch entry.snapshot.healthRaw {
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("环境健康", systemImage: "heart.text.square")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 14, height: 14)
                    Text(entry.snapshot.healthLabel)
                        .font(.title3.bold())
                }
                Text(entry.snapshot.healthDetail ?? "打开启椟查看详情")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.snapshot.outdatedCount)")
                    .font(.title.bold())
                Text("可更新")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }
}

// MARK: - Install progress (medium)

struct KiduxInstallWidget: Widget {
    let kind = "KiduxInstallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KiduxWidgetProvider()) { entry in
            KiduxInstallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("安装进度")
        .description("当前批量安装进度")
        .supportedFamilies([.systemMedium])
    }
}

struct KiduxInstallWidgetView: View {
    let entry: KiduxWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("安装进度", systemImage: "arrow.down.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entry.snapshot.isInstalling {
                Text(entry.snapshot.installTitle ?? "正在安装…")
                    .font(.headline)
                    .lineLimit(1)
                ProgressView(value: min(max(entry.snapshot.installProgress, 0), 1))
                Text("\(Int(entry.snapshot.installProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("当前没有安装任务")
                    .font(.headline)
                Text(entry.snapshot.outdatedCount > 0
                      ? "有 \(entry.snapshot.outdatedCount) 款可更新"
                      : "打开启椟开始装机")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
    }
}

import Foundation

/// S16-01 快照/基准新鲜度（参考 OpenBoot 90 天 stale 提示）
enum SnapshotFreshness {
    static let defaultThresholdDays = 90

    static func isStale(
        exportedAt: Date,
        reference: Date = Date(),
        thresholdDays: Int = defaultThresholdDays
    ) -> Bool {
        guard thresholdDays > 0 else { return false }
        let age = reference.timeIntervalSince(exportedAt)
        return age > TimeInterval(thresholdDays * 86_400)
    }

    static func ageInDays(since date: Date, reference: Date = Date()) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: date, to: reference).day ?? 0)
    }

    static func ageLabel(since date: Date, reference: Date = Date()) -> String {
        let days = ageInDays(since: date, reference: reference)
        if days == 0 { return "今天" }
        return "\(days) 天前"
    }

    static func staleImportAlertMessage(exportedAt: Date, reference: Date = Date()) -> String {
        let exported = exportedAt.formatted(date: .abbreviated, time: .omitted)
        let age = ageLabel(since: exportedAt, reference: reference)
        return """
        该快照导出于 \(exported)（\(age)），已超过 \(defaultThresholdDays) 天。
        brew 包版本、岗位清单与环境状态可能已过时，导入后请核对工具清单再安装。
        """
    }

    static func staleBaselineCaption(capturedAt: Date, reference: Date = Date()) -> String {
        "漂移基准已 \(ageLabel(since: capturedAt, reference: reference))（超过 \(defaultThresholdDays) 天），建议重新「设为基准」或导入新快照。"
    }
}

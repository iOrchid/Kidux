import Foundation
import Observation

/// S19-02 — 本机安装成功率统计（隐私：仅本地，无上报）
struct CatalogToolQuality: Codable, Sendable, Equatable, Identifiable {
    var id: String { toolID }
    var toolID: String
    var attempts: Int
    var successes: Int
    var failures: Int
    var lastUpdated: Date

    var successRate: Double {
        guard attempts > 0 else { return 0 }
        return Double(successes) / Double(attempts)
    }

    var successPercent: Int {
        Int((successRate * 100).rounded())
    }

    /// 展示用徽章：样本不足不显示
    var badge: CatalogQualityBadge? {
        guard attempts >= 2 else { return nil }
        if attempts >= 3, successRate >= 0.85 {
            return .verified
        }
        if successRate < 0.5 {
            return .caution
        }
        if attempts >= 3, successRate >= 0.7 {
            return .solid
        }
        return nil
    }

    var summaryLine: String {
        "本机 \(successes)/\(attempts) 成功（\(successPercent)%）"
    }
}

enum CatalogQualityBadge: String, Sendable {
    case verified
    case solid
    case caution

    var title: String {
        switch self {
        case .verified: return "本机验证"
        case .solid: return "较稳定"
        case .caution: return "易失败"
        }
    }

    var systemImage: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .solid: return "hand.thumbsup.fill"
        case .caution: return "exclamationmark.triangle.fill"
        }
    }
}

private struct CatalogQualityFile: Codable {
    var tools: [String: CatalogToolQuality]
}

/// 本地 Catalog 质量分（基于本机安装结果）
@MainActor
@Observable
final class CatalogQualityStore {
    static let shared = CatalogQualityStore()

    private(set) var qualities: [String: CatalogToolQuality] = [:]

    private var saveTask: Task<Void, Never>?
    private static let saveDebounceNanoseconds: UInt64 = 2_000_000_000

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux/catalog-quality.json")
    }

    private init() {
        load()
    }

    func quality(for toolID: String) -> CatalogToolQuality? {
        qualities[toolID]
    }

    func record(outcomes: [(toolID: String, success: Bool)]) {
        guard !outcomes.isEmpty else { return }
        let now = Date()
        for item in outcomes {
            var entry = qualities[item.toolID] ?? CatalogToolQuality(
                toolID: item.toolID,
                attempts: 0,
                successes: 0,
                failures: 0,
                lastUpdated: now
            )
            entry.attempts += 1
            if item.success {
                entry.successes += 1
            } else {
                entry.failures += 1
            }
            entry.lastUpdated = now
            qualities[item.toolID] = entry
        }
        scheduleSave()
    }

    /// 按成功率排序的 Top N（至少 2 次尝试）
    func topVerified(limit: Int = 8) -> [CatalogToolQuality] {
        qualities.values
            .filter { $0.attempts >= 2 }
            .sorted {
                if $0.successRate != $1.successRate {
                    return $0.successRate > $1.successRate
                }
                return $0.attempts > $1.attempts
            }
            .prefix(limit)
            .map { $0 }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(CatalogQualityFile.self, from: data)
        else {
            qualities = [:]
            return
        }
        qualities = file.tools
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: Self.saveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    private func persistNow() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = CatalogQualityFile(tools: qualities)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

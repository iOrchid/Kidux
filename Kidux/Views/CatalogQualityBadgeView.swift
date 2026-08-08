import SwiftUI

/// S19-02 — Catalog 质量徽章
struct CatalogQualityBadgeView: View {
    let quality: CatalogToolQuality
    var compact: Bool = false

    var body: some View {
        if let badge = quality.badge {
            Label(compact ? badge.title : "\(badge.title) · \(quality.successPercent)%", systemImage: badge.systemImage)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color(for: badge).opacity(0.14), in: Capsule())
                .foregroundStyle(color(for: badge))
                .help(quality.summaryLine)
        } else if quality.attempts > 0 {
            Text(compact ? "\(quality.successPercent)%" : quality.summaryLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help(quality.summaryLine)
        }
    }

    private func color(for badge: CatalogQualityBadge) -> Color {
        switch badge {
        case .verified: return .green
        case .solid: return .blue
        case .caution: return .orange
        }
    }
}

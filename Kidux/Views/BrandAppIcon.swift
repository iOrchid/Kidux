import SwiftUI
import AppKit

/// 启椟品牌图标：与 AppIcon 资源一致
struct BrandAppIcon: View {
    var size: CGFloat
    var showShadow: Bool = true

    private var cornerRadius: CGFloat {
        MacIconStyle.cornerRadius(for: size)
    }

    var body: some View {
        Group {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: showShadow ? .black.opacity(0.16) : .clear,
            radius: size * 0.09,
            y: size * 0.045
        )
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.36, blue: 0.88),
                            Color(red: 0.06, green: 0.58, blue: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
    }
}

extension BrandAppIcon {
    /// 渲染为 NSImage（可用于导出 Dock 图标资源）
    static func renderedImage(size: CGFloat) -> NSImage {
        let view = BrandAppIcon(size: size, showShadow: false)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

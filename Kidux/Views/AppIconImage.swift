import SwiftUI
import AppKit

enum MacIconStyle {
    /// 与 macOS Dock / App Icon squircle 圆角比例一致
    static let cornerRatio: CGFloat = 0.2237

    static func cornerRadius(for size: CGFloat) -> CGFloat {
        size * cornerRatio
    }

    static func applySquircleMask(to image: NSImage, size: CGFloat? = nil) -> NSImage {
        let target = size ?? max(image.size.width, image.size.height)
        let output = NSImage(size: NSSize(width: target, height: target))
        output.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: target, height: target)
        let radius = cornerRadius(for: target)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

        image.draw(
            in: rect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )

        output.unlockFocus()
        return output
    }
}

/// 应用内展示：圆角 + 轻阴影，贴近 macOS 图标风格
struct AppIconImage: View {
    var size: CGFloat
    var showShadow: Bool = true

    private var cornerRadius: CGFloat {
        MacIconStyle.cornerRadius(for: size)
    }

    var body: some View {
        Image(nsImage: maskedAppIcon)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: max(0.5, size * 0.008))
            }
            .shadow(
                color: showShadow ? .black.opacity(0.14) : .clear,
                radius: size * 0.08,
                y: size * 0.04
            )
    }

    private var maskedAppIcon: NSImage {
        NSApp.applicationIconImage
    }
}

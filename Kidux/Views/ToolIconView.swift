import SwiftUI
import AppKit

struct ToolIconView: View {
    let tool: DevTool
    var size: CGFloat = 48

    @State private var image: NSImage?

    private var cornerRadius: CGFloat {
        size * MacIconStyle.cornerRatio
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .padding(size * 0.06)
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: max(0.5, size * 0.012))
        }
        .shadow(color: .black.opacity(0.06), radius: size * 0.06, y: size * 0.03)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        }
        .task(id: tool.id) {
            image = await ToolIconService.shared.icon(for: tool)
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ToolCategoryTheme.swiftUIColor(for: tool.category).gradient)
            Image(systemName: ToolCategoryTheme.symbol(for: tool.category, kind: tool.resolvedKind))
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

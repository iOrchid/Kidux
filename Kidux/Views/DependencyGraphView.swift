import SwiftUI

struct DependencyGraphView: View {
    let root: DependencyTreeNode
    var truncated: Bool = false

    private var layout: DependencyGraphLayout.Result {
        DependencyGraphLayout.layout(root: root)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if truncated {
                Label(String(localized: "ui.DependencyGraphView.541dc160ce"), systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for edge in layout.edges {
                            var path = Path()
                            path.move(to: edge.from)
                            let midY = (edge.from.y + edge.to.y) / 2
                            path.addCurve(
                                to: edge.to,
                                control1: CGPoint(x: edge.from.x, y: midY),
                                control2: CGPoint(x: edge.to.x, y: midY)
                            )
                            context.stroke(
                                path,
                                with: .color(.secondary.opacity(0.45)),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                        }
                    }
                    .frame(width: layout.bounds.width, height: layout.bounds.height)
                    .allowsHitTesting(false)

                    ForEach(layout.nodes) { node in
                        nodeChip(node)
                            .position(node.center)
                    }
                }
                .frame(width: layout.bounds.width, height: layout.bounds.height)
            }
            .frame(minHeight: 220, maxHeight: 400)
            .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.cardStroke)
            )

            Text(String(format: String(localized: "ui.DependencyGraphView.fmt.5696d7a417"), locale: .current, "\(layout.nodes.count)"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func nodeChip(_ node: DependencyGraphLayout.PlacedNode) -> some View {
        Text(node.name)
            .font(.caption.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minWidth: 72, maxWidth: DependencyGraphLayout.defaultLabelWidth)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(node.isRoot ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(node.isRoot ? Color.accentColor.opacity(0.45) : AppTheme.cardStroke, lineWidth: 1)
            }
    }
}

#Preview {
    DependencyGraphView(
        root: DependencyTreeNode(
            name: "node",
            children: [
                DependencyTreeNode(name: "openssl@3", children: []),
                DependencyTreeNode(
                    name: "icu4c",
                    children: [DependencyTreeNode(name: "zlib", children: [])]
                )
            ]
        )
    )
    .padding()
    .frame(width: 520, height: 360)
}

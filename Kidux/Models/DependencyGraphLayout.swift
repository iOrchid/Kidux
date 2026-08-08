import CoreGraphics
import Foundation

enum DependencyGraphLayout {
    struct PlacedNode: Identifiable, Sendable, Hashable {
        let id: String
        let name: String
        let center: CGPoint
        let depth: Int
        let isRoot: Bool
    }

    struct Edge: Sendable, Hashable {
        let from: CGPoint
        let to: CGPoint
    }

    struct Result: Sendable {
        let nodes: [PlacedNode]
        let edges: [Edge]
        let bounds: CGSize
    }

    static let defaultLabelWidth: CGFloat = 108
    static let defaultLabelHeight: CGFloat = 30

    static func layout(
        root: DependencyTreeNode,
        horizontalGap: CGFloat = 28,
        verticalGap: CGFloat = 64,
        labelWidth: CGFloat = defaultLabelWidth,
        labelHeight: CGFloat = defaultLabelHeight
    ) -> Result {
        var leafIndex = 0
        var xUnits: [String: CGFloat] = [:]
        var depthByName: [String: Int] = [:]
        var parentEdges: [(String, String)] = []
        var orderedNames: [String] = []

        func assign(_ node: DependencyTreeNode, depth: Int, parent: String?) {
            depthByName[node.name] = depth
            if !orderedNames.contains(node.name) {
                orderedNames.append(node.name)
            }
            if let parent {
                parentEdges.append((parent, node.name))
            }

            if node.children.isEmpty {
                xUnits[node.name] = CGFloat(leafIndex)
                leafIndex += 1
            } else {
                for child in node.children {
                    assign(child, depth: depth + 1, parent: node.name)
                }
                let childUnits = node.children.compactMap { xUnits[$0.name] }
                if childUnits.isEmpty {
                    xUnits[node.name] = CGFloat(leafIndex)
                    leafIndex += 1
                } else {
                    xUnits[node.name] = childUnits.reduce(0, +) / CGFloat(childUnits.count)
                }
            }
        }

        assign(root, depth: 0, parent: nil)

        let unitWidth = labelWidth + horizontalGap
        let padding: CGFloat = 32
        var nodes: [PlacedNode] = []

        for name in orderedNames {
            let depth = depthByName[name] ?? 0
            let center = CGPoint(
                x: padding + (xUnits[name] ?? 0) * unitWidth + labelWidth / 2,
                y: padding + CGFloat(depth) * verticalGap + labelHeight / 2
            )
            nodes.append(
                PlacedNode(
                    id: name,
                    name: name,
                    center: center,
                    depth: depth,
                    isRoot: name == root.name
                )
            )
        }

        let nodeByName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let halfH = labelHeight / 2
        let edges: [Edge] = parentEdges.compactMap { parent, child in
            guard let fromNode = nodeByName[parent], let toNode = nodeByName[child] else { return nil }
            return Edge(
                from: CGPoint(x: fromNode.center.x, y: fromNode.center.y + halfH),
                to: CGPoint(x: toNode.center.x, y: toNode.center.y - halfH)
            )
        }

        let maxX = nodes.map(\.center.x).max() ?? padding
        let maxY = nodes.map(\.center.y).max() ?? padding
        let bounds = CGSize(
            width: max(maxX + labelWidth / 2 + padding, 280),
            height: max(maxY + labelHeight / 2 + padding, 200)
        )

        return Result(nodes: nodes, edges: edges, bounds: bounds)
    }
}

extension DependencyTreeNode {
    /// 大图截断，避免 brew 深层依赖拖垮 Canvas。
    func graphLimited(maxNodes: Int = 72, maxDepth: Int = 6) -> (node: DependencyTreeNode, truncated: Bool) {
        var count = 0
        var truncated = false

        func trim(_ node: DependencyTreeNode, depth: Int) -> DependencyTreeNode? {
            guard depth <= maxDepth else {
                truncated = true
                return nil
            }
            guard count < maxNodes else {
                truncated = true
                return nil
            }
            count += 1

            var keptChildren: [DependencyTreeNode] = []
            for child in node.children {
                if let trimmed = trim(child, depth: depth + 1) {
                    keptChildren.append(trimmed)
                }
            }
            if keptChildren.count < node.children.count {
                truncated = true
            }
            return DependencyTreeNode(name: node.name, children: keptChildren)
        }

        let trimmed = trim(self, depth: 0) ?? DependencyTreeNode(name: name, children: [])
        return (trimmed, truncated)
    }

    var nodeCount: Int {
        1 + children.reduce(0) { $0 + $1.nodeCount }
    }
}

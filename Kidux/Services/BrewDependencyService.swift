import Foundation

struct DependencyTreeNode: Identifiable, Sendable, Hashable {
    let name: String
    let children: [DependencyTreeNode]

    var id: String { name }

    var isLeaf: Bool { children.isEmpty }

    /// `OutlineGroup` 需要可选子节点；空数组表示叶子。
    var outlineChildren: [DependencyTreeNode]? {
        children.isEmpty ? nil : children
    }
}

private struct DependencyTreeLine: Sendable {
    let depth: Int
    let name: String
}

enum BrewDependencyError: LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// S16-05 formula 依赖树（只读，`brew deps --tree --installed`）
enum BrewDependencyService {
    static func fetchTree(formula: String, mirror: BrewMirror) async -> Result<DependencyTreeNode, BrewDependencyError> {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.message("formula 名称为空")) }

        let homebrew = HomebrewService()
        guard await homebrew.isInstalled() else {
            return .failure(.message("Homebrew 未安装"))
        }

        let shell = ShellExecutor()
        let env = ShellEnvironment.developerEnvironment(extra: mirror.environmentVariables)
        let escaped = trimmed.replacingOccurrences(of: "'", with: "'\\''")
        let result = try? await shell.run(
            "brew deps --tree --installed '\(escaped)' 2>/dev/null",
            environment: env
        )

        guard let result, result.isSuccess else {
            return .failure(.message("无法读取 \(trimmed) 的依赖树"))
        }

        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .failure(.message("\(trimmed) 未安装或没有依赖"))
        }

        return .success(parseTreeOutput(text, fallbackRoot: trimmed))
    }

    static func parseTreeOutput(_ text: String, fallbackRoot: String) -> DependencyTreeNode {
        let rawLines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let first = rawLines.first else {
            return DependencyTreeNode(name: fallbackRoot, children: [])
        }

        var lines: [DependencyTreeLine] = []
        let rootName = cleanTreeLine(first)
        lines.append(DependencyTreeLine(depth: 0, name: rootName.isEmpty ? fallbackRoot : rootName))

        for line in rawLines.dropFirst() {
            let name = cleanTreeLine(line)
            guard !name.isEmpty else { continue }
            lines.append(DependencyTreeLine(depth: treeLineDepth(line), name: name))
        }

        let (root, _) = buildNode(from: lines, start: 0)
        return root
    }

    private static func buildNode(
        from lines: [DependencyTreeLine],
        start: Int
    ) -> (DependencyTreeNode, Int) {
        let current = lines[start]
        var children: [DependencyTreeNode] = []
        var index = start + 1

        while index < lines.count, lines[index].depth > current.depth {
            let (child, nextIndex) = buildNode(from: lines, start: index)
            children.append(child)
            index = nextIndex
        }

        return (DependencyTreeNode(name: current.name, children: children), index)
    }

    private static func treeLineDepth(_ line: String) -> Int {
        var pipeCount = 0
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "│" {
                pipeCount += 1
                index = line.index(after: index)
                while index < line.endIndex, line[index] == " " {
                    index = line.index(after: index)
                }
            } else {
                break
            }
        }
        if line.contains("├──") || line.contains("└──") {
            return pipeCount + 1
        }
        return max(pipeCount, 1)
    }

    private static func cleanTreeLine(_ line: String) -> String {
        var text = line
        while !text.isEmpty {
            if text.hasPrefix("│   ") {
                text = String(text.dropFirst(4))
            } else if text.hasPrefix("    ") {
                text = String(text.dropFirst(4))
            } else if text.hasPrefix("├── ") {
                return String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("└── ") {
                return String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else {
                break
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// S17-04 反向依赖：`brew uses --installed FORMULA`
    static func fetchDependents(formula: String, mirror: BrewMirror) async -> [String] {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let homebrew = HomebrewService()
        guard await homebrew.isInstalled() else { return [] }

        let shell = ShellExecutor()
        let env = ShellEnvironment.developerEnvironment(extra: mirror.environmentVariables)
        let escaped = trimmed.replacingOccurrences(of: "'", with: "'\\''")
        let result = try? await shell.run(
            "brew uses --installed '\(escaped)' 2>/dev/null",
            environment: env
        )

        guard let result, result.isSuccess else { return [] }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }
}

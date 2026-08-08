import Foundation
import Observation

@Observable
final class BundleManager {
    private(set) var roles: [RoleBundle] = []
    private(set) var catalog: [String: DevTool] = [:]
    private(set) var baseOfficeBundle: RoleBundle?
    private(set) var loadError: String?

    private let loader = BundleLoader()

    func load() {
        var errors: [String] = []

        do {
            catalog = try loader.loadCatalog()
        } catch {
            errors.append(error.localizedDescription)
            catalog = Self.fallbackCatalog
        }

        do {
            baseOfficeBundle = try loader.loadBundle(named: "_base_office")
        } catch {
            errors.append(error.localizedDescription)
            baseOfficeBundle = nil
        }

        do {
            roles = try loader.loadAllBundles()
        } catch {
            errors.append(error.localizedDescription)
            roles = roles.isEmpty ? Self.fallbackRoles : roles
        }

        loadError = errors.isEmpty ? nil : errors.joined(separator: "；")
    }

    /// S22-10 — 后台解码 catalog / bundles，再回填到主对象。
    func reloadAsync() async {
        let snapshot = await Task.detached(priority: .userInitiated) { () -> (
            catalog: [String: DevTool],
            roles: [RoleBundle],
            base: RoleBundle?,
            error: String?
        ) in
            let manager = BundleManager()
            manager.load()
            return (manager.catalog, manager.roles, manager.baseOfficeBundle, manager.loadError)
        }.value
        catalog = snapshot.catalog
        roles = snapshot.roles
        baseOfficeBundle = snapshot.base
        loadError = snapshot.error
    }

    func resolveTools(for role: RoleBundle) -> [ResolvedTool] {
        mergeBundles(collectBundles(for: role))
    }

    func resolveTools(for roles: [RoleBundle]) -> [ResolvedTool] {
        let allBundles = roles.flatMap { collectBundles(for: $0) }
        return mergeBundles(allBundles)
    }

    private func collectBundles(for role: RoleBundle) -> [RoleBundle] {
        expandBundle(role, seen: [])
    }

    private func expandBundle(_ bundle: RoleBundle, seen: Set<String>) -> [RoleBundle] {
        var visited = seen
        guard visited.insert(bundle.id).inserted else { return [] }

        var result: [RoleBundle] = []
        if let includes = bundle.includes {
            for includeID in includes {
                if includeID == "_base_office", let base = baseOfficeBundle {
                    result.append(contentsOf: expandBundle(base, seen: visited))
                } else if let included = try? loader.loadBundle(named: includeID) {
                    result.append(contentsOf: expandBundle(included, seen: visited))
                }
            }
        }
        result.append(bundle)
        return result
    }

    private func mergeBundles(_ bundles: [RoleBundle]) -> [ResolvedTool] {
        var map: [String: ResolvedTool] = [:]

        for bundle in bundles {
            for ref in bundle.tools {
                guard let tool = catalog[ref.ref] else { continue }
                let required = ref.required ?? tool.required
                if let existing = map[ref.ref] {
                    map[ref.ref] = ResolvedTool(
                        tool: tool,
                        isRequired: existing.isRequired || required,
                        isSelected: existing.isSelected
                    )
                } else {
                    map[ref.ref] = ResolvedTool(
                        tool: tool,
                        isRequired: required,
                        isSelected: true
                    )
                }
            }
        }

        return map.values.sorted {
            if $0.tool.priority != $1.tool.priority {
                return $0.tool.priority < $1.tool.priority
            }
            return $0.tool.name < $1.tool.name
        }
    }

    func resolvePostInstallSteps(for roles: [RoleBundle]) -> [PostInstallStep] {
        let allBundles = roles.flatMap { collectBundles(for: $0) }
        var seen = Set<String>()
        var steps: [PostInstallStep] = []
        for bundle in allBundles {
            for step in bundle.postInstall ?? [] {
                if seen.insert(step.id).inserted {
                    steps.append(step)
                }
            }
        }
        return steps
    }

    /// 所有岗位 Bundle 引用的工具 ID（去重）
    var allRoleToolIDs: Set<String> {
        var ids = Set<String>()
        for role in roles {
            ids.formUnion(toolIDs(forRoleID: role.id))
        }
        return ids
    }

    func toolIDs(forRoleID roleID: String) -> Set<String> {
        guard let role = roles.first(where: { $0.id == roleID }) else { return [] }
        return toolIDs(for: collectBundles(for: role))
    }

    private func toolIDs(for bundles: [RoleBundle]) -> Set<String> {
        var ids = Set<String>()
        for bundle in bundles {
            for ref in bundle.tools {
                ids.insert(ref.ref)
            }
        }
        return ids
    }

    // MARK: - Fallback data when JSON not bundled yet

    static let fallbackRoles: [RoleBundle] = [
        RoleBundle(
            id: "product_manager",
            name: "产品经理",
            description: "协作、文档、原型与沟通工具",
            icon: "person.crop.rectangle.stack",
            version: "1.0.0",
            includes: ["_base_office"],
            tools: [ToolReference(ref: "xmind", required: nil)]
        ),
        RoleBundle(
            id: "ios_developer",
            name: "App 开发工程师",
            description: "iOS / Android 移动开发环境",
            icon: "iphone",
            version: "1.0.0",
            includes: ["_base_office"],
            tools: [ToolReference(ref: "visual-studio-code", required: nil)]
        ),
        RoleBundle(
            id: "backend_developer",
            name: "后端工程师",
            description: "服务端、数据库与 API 开发",
            icon: "server.rack",
            version: "1.0.0",
            includes: ["_base_office"],
            tools: [ToolReference(ref: "docker", required: nil)]
        ),
        RoleBundle(
            id: "fullstack_developer",
            name: "全栈工程师",
            description: "前后端一体化开发工具集",
            icon: "square.stack.3d.up",
            version: "1.0.0",
            includes: ["_base_office"],
            tools: [ToolReference(ref: "cursor", required: nil)]
        ),
        RoleBundle(
            id: "data_analyst",
            name: "数据分析师",
            description: "Python、Jupyter 与数据可视化",
            icon: "chart.bar.xaxis",
            version: "1.0.0",
            includes: ["_base_office"],
            tools: [ToolReference(ref: "python", required: nil)]
        ),
        RoleBundle(
            id: "designer",
            name: "UI/UX 设计师",
            description: "设计、切图与交付工具",
            icon: "paintbrush",
            version: "1.0.0",
            includes: ["_base_office"],
            tools: [ToolReference(ref: "figma", required: nil)]
        )
    ]

    static let fallbackCatalog: [String: DevTool] = [
        "homebrew": DevTool(
            id: "homebrew", name: "Homebrew", description: "macOS 包管理器",
            category: "infra",
            source: InstallSource(type: .script, identifier: "echo homebrew"),
            required: true, priority: 0
        ),
        "git": DevTool(
            id: "git", name: "Git", description: "版本控制",
            category: "infra",
            source: InstallSource(type: .formula, identifier: "git"),
            priority: 1
        ),
        "iterm2": DevTool(
            id: "iterm2", name: "iTerm2", description: "终端模拟器",
            category: "terminal",
            source: InstallSource(type: .cask, identifier: "iterm2"),
            priority: 10
        ),
        "visual-studio-code": DevTool(
            id: "visual-studio-code", name: "VS Code", description: "代码编辑器",
            category: "editor",
            source: InstallSource(type: .cask, identifier: "visual-studio-code"),
            priority: 30
        ),
        "cursor": DevTool(
            id: "cursor", name: "Cursor", description: "AI 代码编辑器",
            category: "editor",
            source: InstallSource(type: .cask, identifier: "cursor"),
            priority: 30
        ),
        "docker": DevTool(
            id: "docker", name: "Docker", description: "容器平台",
            category: "devops",
            source: InstallSource(type: .cask, identifier: "docker"),
            priority: 40
        ),
        "figma": DevTool(
            id: "figma", name: "Figma", description: "UI 设计",
            category: "design",
            source: InstallSource(type: .cask, identifier: "figma"),
            priority: 40
        ),
        "python": DevTool(
            id: "python", name: "Python 3", description: "Python 运行时",
            category: "language",
            source: InstallSource(type: .formula, identifier: "python"),
            priority: 20
        ),
        "xmind": DevTool(
            id: "xmind", name: "XMind", description: "思维导图",
            category: "product",
            source: InstallSource(type: .cask, identifier: "xmind"),
            priority: 40
        )
    ]
}

import Foundation

enum InstallPreflightSeverity: String, Sendable, Comparable {
    case info
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    static func < (lhs: InstallPreflightSeverity, rhs: InstallPreflightSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

struct InstallPreflightFinding: Identifiable, Sendable, Hashable {
    let id: String
    let toolID: String?
    let toolName: String?
    let severity: InstallPreflightSeverity
    let title: String
    let detail: String
    let suggestion: String?

    init(
        id: String = UUID().uuidString,
        toolID: String? = nil,
        toolName: String? = nil,
        severity: InstallPreflightSeverity,
        title: String,
        detail: String,
        suggestion: String? = nil
    ) {
        self.id = id
        self.toolID = toolID
        self.toolName = toolName
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
    }
}

struct InstallPreflightReport: Sendable {
    let findings: [InstallPreflightFinding]
    let dependencyHints: [String: [String]]
    let analyzedCount: Int

    var highestSeverity: InstallPreflightSeverity {
        findings.map(\.severity).max() ?? .info
    }

    var criticalCount: Int { findings.filter { $0.severity == .critical }.count }
    var warningCount: Int { findings.filter { $0.severity == .warning }.count }

    var summaryLine: String {
        if findings.isEmpty {
            return "未发现明显安装风险（已分析 \(analyzedCount) 项）"
        }
        var parts: [String] = []
        if criticalCount > 0 { parts.append("严重 \(criticalCount)") }
        if warningCount > 0 { parts.append("警告 \(warningCount)") }
        let info = findings.count - criticalCount - warningCount
        if info > 0 { parts.append("提示 \(info)") }
        return "依赖分析：\(parts.joined(separator: " · "))"
    }

    var blocksInstall: Bool { criticalCount > 0 }
}

/// S18-14 — 安装前依赖 / 冲突 / 环境风险分析（规则层；可挂 Dry-run）
enum InstallPreflightService {
    static func analyze(
        tools: [ResolvedTool],
        enableMAS: Bool,
        skipInstalled: Bool,
        snapshot: InstalledStatusSnapshot?,
        environment: EnvironmentStatus,
        mirror: BrewMirror
    ) async -> InstallPreflightReport {
        let selected = tools.filter(\.isSelected)
        var findings: [InstallPreflightFinding] = []
        var dependencyHints: [String: [String]] = [:]

        // 新机小白常见顺序：先 CLT（含 git）→ 再 Homebrew → 才能装其它软件
        if !environment.hasCommandLineTools {
            findings.append(
                InstallPreflightFinding(
                    severity: .critical,
                    title: "未安装命令行工具（CLT）",
                    detail: "新 Mac 通常还没有 Xcode Command Line Tools（含 git）。没有它时无法安装 Homebrew，后续软件也会失败。",
                    suggestion: "请先安装命令行工具：系统会弹出安装窗口，完成后回到启椟再点「开始安装」"
                )
            )
        }

        if !environment.hasHomebrew {
            // 有 CLT 时降为警告：允许继续，由 InstallManager 自动装 Homebrew
            // 无 CLT 时标严重（与上方 CLT 项叠加），禁止硬闯装软件
            findings.append(
                InstallPreflightFinding(
                    severity: environment.hasCommandLineTools ? .warning : .critical,
                    title: "Homebrew 未就绪",
                    detail: environment.hasCommandLineTools
                        ? "检测不到 brew。继续安装时，启椟会先自动安装 Homebrew，再装你勾选的软件。"
                        : "检测不到 brew。请先安装命令行工具（CLT），再装 Homebrew。",
                    suggestion: environment.hasCommandLineTools
                        ? "可继续安装；首次装 Homebrew 需网络与管理员密码"
                        : "请先完成 CLT 安装，不要跳过环境准备"
                )
            )
        }

        if !environment.hasSufficientDiskSpace {
            findings.append(
                InstallPreflightFinding(
                    severity: .critical,
                    title: "磁盘空间不足",
                    detail: "可用空间 \(environment.diskSpaceLabel)，低于建议阈值 \(Int(EnvironmentStatus.minimumDiskGB)) GB。",
                    suggestion: "清理磁盘或减少勾选体积较大的工具后再装"
                )
            )
        }

        if mirror != .official {
            findings.append(
                InstallPreflightFinding(
                    severity: .info,
                    title: "正在使用国内镜像",
                    detail: "当前镜像：\(mirror.rawValue)。部分新包可能同步滞后。",
                    suggestion: "若安装失败可在设置中切换官方源重试"
                )
            )
        }

        let brewTools = selected.filter { tool in
            let t = tool.tool
            let installed = snapshot?.state(for: t) == .installed
            if skipInstalled && installed { return false }
            return t.source.type == .formula || t.source.type == .cask
        }

        for resolved in selected {
            let tool = resolved.tool
            let installed = snapshot?.state(for: tool) == .installed

            if tool.source.type == .mas, !enableMAS {
                findings.append(
                    InstallPreflightFinding(
                        toolID: tool.id,
                        toolName: tool.name,
                        severity: .warning,
                        title: "App Store 安装已关闭",
                        detail: "\(tool.name) 需要 mas-cli，但设置中已关闭 MAS。",
                        suggestion: "在设置中开启「允许 Mac App Store 安装」，或取消勾选该项"
                    )
                )
            }

            if tool.source.type == .link {
                findings.append(
                    InstallPreflightFinding(
                        toolID: tool.id,
                        toolName: tool.name,
                        severity: .info,
                        title: "需手动安装",
                        detail: "\(tool.name) 仅提供官网外链，应用内不会自动下载。",
                        suggestion: tool.resolvedHomepage ?? tool.source.identifier
                    )
                )
            }

            if tool.source.type == .script, !(skipInstalled && installed) {
                findings.append(
                    InstallPreflightFinding(
                        toolID: tool.id,
                        toolName: tool.name,
                        severity: .info,
                        title: "将运行内置脚本",
                        detail: "脚本：\(tool.source.identifier)。请确认网络可访问官方安装源。",
                        suggestion: nil
                    )
                )
            }
        }

        if environment.hasHomebrew, !brewTools.isEmpty {
            let homebrew = HomebrewService()
            let brewPath = await homebrew.brewPath
            let shell = ShellExecutor()
            let env = ShellEnvironment.developerEnvironment(extra: mirror.environmentVariables)
            let identifiers = brewTools.map(\.tool.source.identifier)
            let batch = identifiers.prefix(24).map {
                $0.replacingOccurrences(of: "'", with: "'\\''")
            }.joined(separator: "' '")

            if let result = try? await shell.run(
                "\(brewPath) info --json=v2 '\(batch)' 2>/dev/null",
                environment: env
            ), result.isSuccess,
               let data = result.stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parseBrewInfo(
                    json: json,
                    tools: brewTools.map(\.tool),
                    findings: &findings,
                    dependencyHints: &dependencyHints
                )
            } else if brewTools.count > 8 {
                findings.append(
                    InstallPreflightFinding(
                        severity: .info,
                        title: "未能批量读取 brew 元数据",
                        detail: "已跳过详细依赖探测，仍可继续安装；网络或镜像异常时建议先执行 brew update。",
                        suggestion: "检查网络，或在终端运行 brew update"
                    )
                )
            }
        }

        // Docker Desktop 类常见坑
        if let docker = selected.first(where: { $0.tool.id == "docker" || $0.tool.source.identifier == "docker" }),
           snapshot?.state(for: docker.tool) != .installed || !skipInstalled {
            findings.append(
                InstallPreflightFinding(
                    toolID: docker.tool.id,
                    toolName: docker.tool.name,
                    severity: .info,
                    title: "Docker 体积较大",
                    detail: "Docker Desktop 安装与首次启动耗时较长，并可能请求权限。",
                    suggestion: "安装完成后在「已安装」页确认可打开"
                )
            )
        }

        findings.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return (lhs.toolName ?? "") < (rhs.toolName ?? "")
        }

        return InstallPreflightReport(
            findings: findings,
            dependencyHints: dependencyHints,
            analyzedCount: selected.count
        )
    }

    private static func parseBrewInfo(
        json: [String: Any],
        tools: [DevTool],
        findings: inout [InstallPreflightFinding],
        dependencyHints: inout [String: [String]]
    ) {
        let byID = Dictionary(uniqueKeysWithValues: tools.map { ($0.source.identifier.lowercased(), $0) })

        func handleEntries(_ entries: [[String: Any]], isCask: Bool) {
            for entry in entries {
                let token = ((entry["token"] as? String) ?? (entry["name"] as? String) ?? "")
                    .lowercased()
                guard let tool = byID[token] ?? byID[entry["full_name"] as? String ?? ""] else { continue }

                var deps: [String] = []
                if let depends = entry["dependencies"] as? [String] {
                    deps.append(contentsOf: depends)
                }
                if let depends = entry["depends_on"] as? [String: Any] {
                    if let formula = depends["formula"] as? [String] { deps.append(contentsOf: formula) }
                    if let cask = depends["cask"] as? [String] { deps.append(contentsOf: cask) }
                    if let macos = depends["macos"] as? [String: Any], !macos.isEmpty {
                        findings.append(
                            InstallPreflightFinding(
                                toolID: tool.id,
                                toolName: tool.name,
                                severity: .info,
                                title: "系统版本要求",
                                detail: "\(tool.name) 声明了 macOS 版本约束。",
                                suggestion: "若安装失败请核对系统版本是否满足"
                            )
                        )
                    }
                }
                if let runtime = entry["depends_on"] as? [String], !runtime.isEmpty {
                    deps.append(contentsOf: runtime)
                }

                let uniqueDeps = Array(Set(deps)).sorted()
                if !uniqueDeps.isEmpty {
                    dependencyHints[tool.id] = uniqueDeps
                    if uniqueDeps.count >= 8 {
                        findings.append(
                            InstallPreflightFinding(
                                toolID: tool.id,
                                toolName: tool.name,
                                severity: .warning,
                                title: "依赖较多",
                                detail: "\(tool.name) 将顺带安装约 \(uniqueDeps.count) 个依赖：\(uniqueDeps.prefix(6).joined(separator: ", "))\(uniqueDeps.count > 6 ? "…" : "")",
                                suggestion: "预计耗时与磁盘占用会更高"
                            )
                        )
                    }
                }

                if let conflicts = entry["conflicts_with"] as? [String], !conflicts.isEmpty {
                    findings.append(
                        InstallPreflightFinding(
                            toolID: tool.id,
                            toolName: tool.name,
                            severity: .warning,
                            title: "可能存在冲突包",
                            detail: "\(tool.name) 与 \(conflicts.joined(separator: ", ")) 冲突。",
                            suggestion: "安装前请卸载冲突软件，或取消勾选"
                        )
                    )
                }
                if let conflicts = entry["conflicts_with"] as? [String: Any] {
                    var names: [String] = []
                    if let f = conflicts["formula"] as? [String] { names.append(contentsOf: f) }
                    if let c = conflicts["cask"] as? [String] { names.append(contentsOf: c) }
                    if !names.isEmpty {
                        findings.append(
                            InstallPreflightFinding(
                                toolID: tool.id,
                                toolName: tool.name,
                                severity: .warning,
                                title: "可能存在冲突包",
                                detail: "\(tool.name) 与 \(names.joined(separator: ", ")) 冲突。",
                                suggestion: "安装前请卸载冲突软件，或取消勾选"
                            )
                        )
                    }
                }

                if isCask, let caveats = entry["caveats"] as? String, !caveats.isEmpty {
                    let short = caveats
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if short.count > 20 {
                        findings.append(
                            InstallPreflightFinding(
                                toolID: tool.id,
                                toolName: tool.name,
                                severity: .info,
                                title: "安装注意事项",
                                detail: String(short.prefix(160)) + (short.count > 160 ? "…" : ""),
                                suggestion: nil
                            )
                        )
                    }
                }
            }
        }

        if let formulae = json["formulae"] as? [[String: Any]] {
            handleEntries(formulae, isCask: false)
        }
        if let casks = json["casks"] as? [[String: Any]] {
            handleEntries(casks, isCask: true)
        }
    }
}

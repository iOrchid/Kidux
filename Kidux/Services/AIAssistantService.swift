import Foundation

enum AIChatRole: String, Sendable {
    case user
    case assistant
    case system
}

struct AIChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: AIChatRole
    var text: String
    var isStreaming: Bool = false
    let timestamp: Date
    var actionLabel: String?
    var actionTab: AppTab?
    /// 点击后打开 AI 设置（配置 API Key）
    var opensAISettings: Bool
    /// S12-02：对话内软件推荐卡片
    var recommendedToolIDs: [String]

    init(
        id: UUID = UUID(),
        role: AIChatRole,
        text: String,
        isStreaming: Bool = false,
        timestamp: Date = Date(),
        actionLabel: String? = nil,
        actionTab: AppTab? = nil,
        opensAISettings: Bool = false,
        recommendedToolIDs: [String] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.timestamp = timestamp
        self.actionLabel = actionLabel
        self.actionTab = actionTab
        self.opensAISettings = opensAISettings
        self.recommendedToolIDs = recommendedToolIDs
    }
}

struct AIAssistantReply: Sendable {
    let text: String
    let actionLabel: String?
    let actionTab: AppTab?
    let suggestedFollowUps: [String]
}

enum AIAssistantService {
    static func welcomeMessage(hasAPIKey: Bool) -> AIChatMessage {
        if hasAPIKey {
            return AIChatMessage(
                role: .assistant,
                text: """
                你好，我是 **\(BrandInfo.assistantName)**。云端 AI 已就绪。

                可以直接说，例如：

                - 帮我配置全栈 / 前端环境
                - 推荐效率工具
                - 检查软件更新、修复「应用已损坏」
                """
            )
        }
        return AIChatMessage(
            role: .assistant,
            text: """
            你好，我是 **\(BrandInfo.assistantName)**。

            **不用 AI 也能装软件**：选岗位 → 勾选工具 → 一键安装。

            想用自然语言对话（更智能）时，需要自己的 API Key（有免费额度即可）：

            1. 打开硅基流动（cloud.siliconflow.cn）或 DeepSeek（platform.deepseek.com）注册
            2. 创建 API Key 并复制
            3. 点下方按钮粘贴，并打开「启用云端 AI」

            未配置时，我只能用本地规则回答（例如识别「装前端环境」），无法自由闲聊。
            """,
            actionLabel: "配置 API Key",
            opensAISettings: true
        )
    }

    /// 兼容旧调用
    static var welcome: AIChatMessage { welcomeMessage(hasAPIKey: false) }

    static func missingAPIKeyTip() -> AIChatMessage {
        AIChatMessage(
            role: .assistant,
            text: """
            刚才用的是 **本地规则**，不是大模型。

            若回答不够智能：点下方配置 API Key（硅基流动 / DeepSeek），开启云端 AI 后再问一次。岗位一键安装不依赖 Key。
            """,
            actionLabel: "去配置 API Key",
            opensAISettings: true
        )
    }

    static let suggestedPrompts = [
        "帮我配置全栈开发环境",
        "推荐开源效率工具",
        "检查哪些软件可以更新",
        "应用提示已损坏怎么办"
    ]

    @MainActor
    static func systemPrompt(for viewModel: AppViewModel) -> String {
        let roleNames = viewModel.bundleManager.roles.map(\.name).joined(separator: "、")
        return """
        你是「\(BrandInfo.fullTitle)」的 Mac 装机 AI 助手。产品帮助互联网从业者在新 Mac 上一键配置开发环境。
        能力：岗位 Bundle 一键安装、发现页 brew/mas 安装、已安装扫描、brew 更新检查、Gatekeeper/xattr 修复引导。
        可选岗位：\(roleNames)
        软件目录约 \(viewModel.allCatalogTools.count) 款。回复用简洁中文，步骤清晰，不超过 300 字。
        不要编造不存在的功能。破解软件不提供，可引导官方 brew 替代。
        """
    }

    @MainActor
    static func agentSystemPrompt(for viewModel: AppViewModel) -> String {
        let roleList = viewModel.bundleManager.roles
            .map { "\($0.id)=\($0.name)" }
            .joined(separator: "；")
        return """
        你是 Kidux 装机 Agent。可用工具：search_catalog（搜软件）、scan_installed（扫描本机）、select_role（选岗位）、install_tools（加入清单或安装）。
        用户要装软件时先 search_catalog 或 select_role，再询问是否安装；用户明确说「直接安装」时才 install_tools(auto_install=true)。
        岗位 id 列表：\(roleList)
        回复简洁中文。执行工具后根据结果向用户说明，可推荐 3–8 款相关软件 id。
        """
    }

    static func enrichLLMResponse(_ text: String, userInput: String, nlPlan: NLInstallPlan? = nil) -> AIAssistantReply {
        let rules = reply(to: userInput, nlPlan: nlPlan)
        return AIAssistantReply(
            text: text,
            actionLabel: rules.actionLabel,
            actionTab: rules.actionTab,
            suggestedFollowUps: rules.suggestedFollowUps
        )
    }

    static func reply(to input: String, nlPlan: NLInstallPlan? = nil) -> AIAssistantReply {
        if let plan = nlPlan {
            return replyForNLPlan(plan)
        }
        let q = input.lowercased()

        if matches(q, any: ["全栈", "fullstack", "full stack", "全端"]) {
            return AIAssistantReply(
                text: "全栈工程师岗位包含前端、后端与通用办公工具。我可以带你进入岗位配置，一键勾选并安装。",
                actionLabel: "去配置全栈环境",
                actionTab: .roles,
                suggestedFollowUps: ["推荐终端工具", "查看已安装"]
            )
        }

        if matches(q, any: ["前端", "frontend", "react", "vue"]) {
            return AIAssistantReply(
                text: "前端岗位预设 VS Code、Chrome、Node 生态等工具。进入岗位页选择「前端开发工程师」即可预览清单。",
                actionLabel: "去选前端岗位",
                actionTab: .roles,
                suggestedFollowUps: ["推荐效率工具"]
            )
        }

        if matches(q, any: ["后端", "backend", "java", "python", "go"]) {
            return AIAssistantReply(
                text: "后端有 Java / Python / Go 等细分岗位。建议从岗位配置进入，按语言选择对应 Bundle。",
                actionLabel: "去选后端岗位",
                actionTab: .roles,
                suggestedFollowUps: ["帮我装 Docker"]
            )
        }

        if matches(q, any: ["效率", "开源", "工具推荐", "必备", "awesome"]) {
            return AIAssistantReply(
                text: "发现页已收录 Raycast、Rectangle、Stats、Maccy 等开源/免费效率工具。可切换到「精选热门」或「范围 → 岗位推荐」筛选。",
                actionLabel: "去发现页",
                actionTab: .discover,
                suggestedFollowUps: ["装 iTerm2", "社区资源在哪"]
            )
        }

        if matches(q, any: ["损坏", "xattr", "隔离", "quarantine", "打不开", "无法打开", "隐私", "安全"]) {
            return AIAssistantReply(
                text: """
                这通常是 macOS Gatekeeper 拦截或下载隔离属性导致：

                1. 打开 **已安装 → 本机应用**，点该应用旁的 **「修复」**
                2. 一键清除 `com.apple.quarantine` 隔离属性
                3. 若仍被拦截，点 **「打开隐私与安全性」**，在「通用」里点 **「仍要打开」**

                brew 安装的 cask 一般不需要额外操作；手动下载的 DMG 更常见此问题。
                """,
                actionLabel: "去已安装页修复",
                actionTab: .installed,
                suggestedFollowUps: ["继续安装其他软件"]
            )
        }

        if matches(q, any: ["iterm", "raycast", "vscode", "cursor", "chrome", "安装"]) {
            return AIAssistantReply(
                text: "单个或多个软件可在发现页搜索名称，点「获取」即可通过 Homebrew 安装。支持批量勾选后一键安装。",
                actionLabel: "去发现页搜索",
                actionTab: .discover,
                suggestedFollowUps: ["查看安装进度", "配置开发环境"]
            )
        }

        if matches(q, any: ["xclient", "破解", "haxmac", "社区", "第三方"]) {
            return AIAssistantReply(
                text: """
                \(BrandInfo.displayNameCN) **不在应用内分发破解包**（版权与安全原因）。

                你可以在 **设置 → 允许社区资源参考** 开启后，于发现页底部访问 xclient / haxmac 外链，并查看「社区热门 → 官方 brew 替代」一键安装。
                """,
                actionLabel: "去发现页",
                actionTab: .discover,
                suggestedFollowUps: ["推荐正版替代品"]
            )
        }

        if looksLikeInstallError(input) {
            return diagnoseInstallLog(input)
        }

        if matches(q, any: ["进度", "停止", "取消", "密码"]) {
            return AIAssistantReply(
                text: """
                安装过程中请注意：

                - 弹窗内可 **停止** / **跳过剩余** / **后台继续**
                - 右侧 **实时日志** 会输出 brew 过程
                - 若需管理员权限，请在系统密码框输入 Mac 登录密码

                若界面无反应，请确认运行的是最新构建。
                """,
                actionLabel: nil,
                actionTab: nil,
                suggestedFollowUps: ["应用打不开怎么办"]
            )
        }

        if matches(q, any: ["已安装", "本机", "扫描"]) {
            return AIAssistantReply(
                text: "已安装页会扫描 /Applications 与 brew/mas 目录匹配结果，支持打开应用与 Gatekeeper 修复。",
                actionLabel: "查看已安装",
                actionTab: .installed,
                suggestedFollowUps: ["检查软件更新"]
            )
        }

        if matches(q, any: ["帮我装", "一键安装", "批量装", "装这些"]) {
            return AIAssistantReply(
                text: "可以在发现页搜索软件名，勾选后点「安装选中项」。也可以说具体软件，例如「装 Docker 和 iTerm2」。",
                actionLabel: "去发现页",
                actionTab: .discover,
                suggestedFollowUps: ["配置全栈环境", "查看安装进度"]
            )
        }

        if matches(q, any: ["更新", "升级", "outdated", "upgrade", "新版本"]) {
            return AIAssistantReply(
                text: "\(BrandInfo.displayNameCN)可通过 `brew outdated` 检查 Homebrew 已安装项是否有新版本。打开已安装页 →「可更新」查看并一键升级。",
                actionLabel: "检查更新",
                actionTab: .installed,
                suggestedFollowUps: ["推荐效率工具", "配置开发环境"]
            )
        }

        return AIAssistantReply(
            text: """
            我还不能完全理解这句话，可以试试：

            - 描述你的 **岗位**（如「数据分析师新机配置」）
            - 说出 **软件名**（如「装 Typora 和 Obsidian」）
            - 提问 **安装问题**（如「提示已损坏」）

            后续版本将支持更自由的 NL 自动编排安装。
            """,
            actionLabel: "浏览发现页",
            actionTab: .discover,
            suggestedFollowUps: suggestedPrompts
        )
    }

    private static func replyForNLPlan(_ plan: NLInstallPlan) -> AIAssistantReply {
        if let role = plan.matchedRole, plan.matchedTools.isEmpty {
            return AIAssistantReply(
                text: """
                已识别并预选岗位 **\(role.name)**（约 \(role.toolCount) 款工具）。

                请在岗位配置页确认清单，然后点击开始安装。
                """,
                actionLabel: "查看岗位清单",
                actionTab: .roles,
                suggestedFollowUps: ["推荐效率工具", "检查软件更新"]
            )
        }

        if !plan.matchedTools.isEmpty, plan.matchedRole == nil {
            let names = plan.matchedTools.map(\.name).joined(separator: "、")
            return AIAssistantReply(
                text: """
                已在发现页预选以下软件：**\(names)**

                你可以前往发现页确认并批量安装。
                """,
                actionLabel: "去发现页安装",
                actionTab: .discover,
                suggestedFollowUps: ["配置开发环境", "查看已安装"]
            )
        }

        if let role = plan.matchedRole {
            let names = plan.matchedTools.map(\.name).joined(separator: "、")
            return AIAssistantReply(
                text: """
                已预选岗位 **\(role.name)**，并额外选中软件：\(names)

                建议先在岗位页确认 Bundle，再在发现页安装额外软件。
                """,
                actionLabel: "查看岗位清单",
                actionTab: .roles,
                suggestedFollowUps: ["去发现页", "开始安装"]
            )
        }

        return reply(to: "", nlPlan: nil)
    }

    private static func matches(_ text: String, any keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func looksLikeInstallError(_ text: String) -> Bool {
        let t = text.lowercased()
        guard text.count > 60 else { return false }
        return t.contains("error") || t.contains("failed") || t.contains("fatal")
            || (t.contains("brew") && (t.contains("install") || t.contains("cask")))
            || t.contains("command not found") || t.contains("permission denied")
    }

    /// 安装完成摘要（v1.1 — 完成页 / AI 助手）
    static func installCompletionSummary(summary: InstallSummary, roleName: String?) -> String {
        var lines: [String] = []
        lines.append("本次安装已完成。")
        if let roleName {
            lines.append("岗位：**\(roleName)**")
        }
        lines.append("成功 \(summary.succeeded) · 跳过 \(summary.skipped) · 失败 \(summary.failed) · 共 \(summary.total) 项")

        if summary.failed > 0 {
            lines.append("")
            lines.append("有失败项时建议：")
            lines.append("1. 在安装进度页点「重试」或「AI 分析失败」")
            lines.append("2. 设置中切换 Homebrew 国内镜像")
            lines.append("3. 到已安装页检查 Gatekeeper / 修复")
        } else if summary.succeeded > 0 {
            lines.append("")
            lines.append("下一步可在 **已安装** 查看软件，或在 **发现** 继续补装工具。")
        }
        return lines.joined(separator: "\n")
    }

    static func diagnoseInstallLog(_ text: String) -> AIAssistantReply {
        InstallDiagnosisService.diagnoseRules(text)
    }
}

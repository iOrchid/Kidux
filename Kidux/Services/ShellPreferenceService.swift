import Foundation

/// S17-12 — 终端 Shell 偏好（影响 postInstall：omz vs fish）
enum PreferredShell: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case zsh
    case fish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统登录 Shell"
        case .zsh: return "Zsh（Oh My Zsh）"
        case .fish: return "Fish"
        }
    }

    var summary: String {
        switch self {
        case .system: return "根据 $SHELL 自动选择 zsh 或 fish 配置路径"
        case .zsh: return "使用 Oh My Zsh / zsh 插件 / starship init zsh"
        case .fish: return "跳过 Oh My Zsh，配置 ~/.config/fish 与 starship init fish"
        }
    }
}

enum ShellPreferenceService {
    static func effectiveShell(from preference: PreferredShell) -> PreferredShell {
        switch preference {
        case .zsh, .fish:
            return preference
        case .system:
            let shell = ProcessInfo.processInfo.environment["SHELL"]?.lowercased() ?? ""
            if shell.contains("fish") { return .fish }
            return .zsh
        }
    }

    static func scriptEnvironment(preferred: PreferredShell) -> [String: String] {
        let effective = effectiveShell(from: preferred)
        return ["KIDUX_SHELL": effective == .fish ? "fish" : "zsh"]
    }

    /// 按偏好改写岗位 postInstall：Fish 跳过 omz/zsh-plugins，注入 fish 配置
    static func adaptPostInstall(
        _ steps: [PostInstallStep],
        preferred: PreferredShell
    ) -> [PostInstallStep] {
        let effective = effectiveShell(from: preferred)
        guard effective == .fish else { return steps }

        var adapted: [PostInstallStep] = []
        var insertedFish = false
        var seen = Set<String>()

        for step in steps {
            switch step.id {
            case "omz", "zsh-plugins":
                continue
            case "starship":
                let fishStarship = PostInstallStep(
                    id: "starship",
                    name: "Starship（Fish）",
                    script: "configure_starship.sh",
                    skipIf: #"grep -q 'starship init fish' "$HOME/.config/fish/config.fish" 2>/dev/null"#
                )
                if seen.insert(fishStarship.id).inserted {
                    adapted.append(fishStarship)
                }
            default:
                if seen.insert(step.id).inserted {
                    adapted.append(step)
                }
            }
        }

        let fishStep = PostInstallStep(
            id: "fish-config",
            name: "Fish 配置",
            script: "configure_fish.sh",
            skipIf: #"grep -q 'Kidux — Fish' "$HOME/.config/fish/config.fish" 2>/dev/null"#
        )
        if seen.insert(fishStep.id).inserted {
            // 放在 starship 之前更合理：先建 config.fish
            if let idx = adapted.firstIndex(where: { $0.id == "starship" }) {
                adapted.insert(fishStep, at: idx)
            } else {
                adapted.insert(fishStep, at: 0)
            }
            insertedFish = true
        }
        _ = insertedFish
        return adapted
    }
}

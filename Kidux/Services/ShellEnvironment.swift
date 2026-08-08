import Foundation

/// macOS GUI 应用启动时 PATH 往往不含 Homebrew，需补全开发者常用路径。
enum ShellEnvironment {
    private static let developerPathPrefixes = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "\(NSHomeDirectory())/.local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func developerEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var parts: [String] = []
        var seen = Set<String>()

        for segment in developerPathPrefixes + (env["PATH"] ?? "").split(separator: ":").map(String.init) {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            parts.append(trimmed)
        }

        env["PATH"] = parts.joined(separator: ":")
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    /// `command -v` 失败时，在常见目录直接查找可执行文件。
    static func resolveExecutable(named command: String) -> String? {
        let fm = FileManager.default
        for prefix in developerPathPrefixes {
            let path = (prefix as NSString).appendingPathComponent(command)
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

import Foundation

enum RepoPaths {
    static func resolveRoot() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["KIDUX_REPO_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }

        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let fm = FileManager.default
        for _ in 0..<8 {
            let marker = dir.appendingPathComponent("Kidux.xcodeproj")
            if fm.fileExists(atPath: marker.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }

        throw KiduxCLIError.repoRootNotFound
    }

    static func catalogURL(root: URL) -> URL {
        root.appendingPathComponent("Kidux/Resources/bundles/catalog.json")
    }

    static func bundleURL(root: URL, roleID: String) -> URL {
        root.appendingPathComponent("Kidux/Resources/bundles/\(roleID).json")
    }

    static func bundlesDirectory(root: URL) -> URL {
        root.appendingPathComponent("Kidux/Resources/bundles")
    }

    static func scriptsDirectory(root: URL) -> URL {
        root.appendingPathComponent("Kidux/Resources/scripts")
    }
}

enum KiduxCLIError: LocalizedError {
    case repoRootNotFound
    case fileNotFound(String)
    case invalidSnapshot(String)
    case bundleNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .repoRootNotFound:
            return "找不到 Kidux 仓库根目录。请 cd 到 Kidux 目录，或设置 KIDUX_REPO_ROOT。"
        case .fileNotFound(let path):
            return "文件不存在：\(path)"
        case .invalidSnapshot(let reason):
            return "快照无效：\(reason)"
        case .bundleNotFound(let id):
            return "找不到岗位 Bundle：\(id)"
        case .commandFailed(let output):
            return "命令执行失败：\(output)"
        }
    }
}

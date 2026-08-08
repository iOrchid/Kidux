import Foundation

/// 用户导入的扩展软件目录（Application Support/Kidux/extended-catalog.json）
enum ExtendedCatalogStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux", isDirectory: true)
    }

    static var catalogFileURL: URL {
        directory.appendingPathComponent("extended-catalog.json")
    }

    static var importedCount: Int { load().count }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func load() -> [DevTool] {
        guard FileManager.default.fileExists(atPath: catalogFileURL.path),
              let data = try? Data(contentsOf: catalogFileURL),
              let catalog = try? JSONDecoder().decode(ToolCatalog.self, from: data)
        else { return [] }
        return catalog.tools
    }

    @discardableResult
    static func importFrom(_ sourceURL: URL) throws -> Int {
        let data = try Data(contentsOf: sourceURL)
        let catalog = try JSONDecoder().decode(ToolCatalog.self, from: data)
        guard !catalog.tools.isEmpty else {
            throw ExtendedCatalogError.emptyCatalog
        }
        try ensureDirectory()
        try data.write(to: catalogFileURL, options: .atomic)
        return catalog.tools.count
    }

    static func clear() throws {
        guard FileManager.default.fileExists(atPath: catalogFileURL.path) else { return }
        try FileManager.default.removeItem(at: catalogFileURL)
    }
}

enum ExtendedCatalogError: LocalizedError {
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .emptyCatalog: return "JSON 中未找到有效工具条目"
        }
    }
}

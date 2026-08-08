import Foundation

enum BundleLoaderError: LocalizedError {
    case catalogNotFound
    case bundleNotFound(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .catalogNotFound:
            return "找不到工具目录 catalog.json"
        case .bundleNotFound(let name):
            return "找不到 Bundle: \(name)"
        case .decodeFailed(let name):
            return "解析失败: \(name)"
        }
    }
}

struct BundleLoader {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    func loadCatalog() throws -> [String: DevTool] {
        let data = try loadResourceData(named: "catalog", subdirectory: "bundles")
        let catalog = try decoder.decode(ToolCatalog.self, from: data)
        var map = Dictionary(uniqueKeysWithValues: catalog.tools.map { ($0.id, $0) })
        mergeAddonCatalog(into: &map, named: "efficiency-tools-addon")
        mergeAddonCatalog(into: &map, named: "ai-tools-addon")
        mergeExtendedCatalog(into: &map)
        return map
    }

    private func mergeExtendedCatalog(into map: inout [String: DevTool]) {
        for tool in ExtendedCatalogStore.load() {
            map[tool.id] = tool
        }
    }

    private func mergeAddonCatalog(into map: inout [String: DevTool], named name: String) {
        guard let data = try? loadResourceData(named: name, subdirectory: "bundles"),
              let addon = try? decoder.decode(ToolCatalog.self, from: data)
        else { return }
        for tool in addon.tools where map[tool.id] == nil {
            map[tool.id] = tool
        }
    }

    func loadAllBundles() throws -> [RoleBundle] {
        let bundleNames = [
            "student_starter",
            "product_manager",
            "operations_specialist",
            "designer",
            "frontend_developer",
            "backend_developer",
            "fullstack_developer",
            "java_developer",
            "python_developer",
            "golang_developer",
            "ios_developer",
            "android_developer",
            "mobile_developer",
            "data_analyst",
            "data_engineer",
            "algorithm_engineer",
            "qa_engineer",
            "security_engineer",
            "devops_engineer",
            "sre_engineer",
            "ai_developer"
        ]

        var loaded: [RoleBundle] = []
        var errors: [String] = []

        for name in bundleNames {
            do {
                loaded.append(try loadBundle(named: name))
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        if loaded.isEmpty {
            throw BundleLoaderError.decodeFailed(errors.joined(separator: "；"))
        }

        return loaded
    }

    func loadBundle(named name: String) throws -> RoleBundle {
        let data = try loadResourceData(named: name, subdirectory: "bundles")
        do {
            return try decoder.decode(RoleBundle.self, from: data)
        } catch {
            throw BundleLoaderError.decodeFailed(name)
        }
    }

    private func loadResourceData(named name: String, subdirectory: String) throws -> Data {
        // Xcode Copy Bundle Resources 会把 JSON 平铺到 Resources 根目录
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "json"),
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory),
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources/\(subdirectory)"),
            devResourceURL(named: name)
        ]

        for url in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }

        throw BundleLoaderError.bundleNotFound(name)
    }

    private func devResourceURL(named name: String) -> URL? {
        let devRoot = Bundle.main.bundlePath
            .replacingOccurrences(of: "/Build/Products/Debug/Kidux.app", with: "")
        let candidate = URL(fileURLWithPath: devRoot)
            .appendingPathComponent("Kidux/Resources/bundles/\(name).json")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}

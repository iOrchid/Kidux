import Foundation

struct LocalApplication: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String?
    var isInCatalog: Bool
    var catalogToolID: String?

    init(
        id: String,
        name: String,
        path: String,
        bundleIdentifier: String?,
        isInCatalog: Bool = false,
        catalogToolID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.isInCatalog = isInCatalog
        self.catalogToolID = catalogToolID
    }
}

actor LocalApplicationsScanner {
    func scan(matching catalog: [String: DevTool]) -> [LocalApplication] {
        var results: [LocalApplication] = []
        let fm = FileManager.default
        let index = buildCatalogIndex(catalog)

        let searchPaths = [
            "/Applications",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        for base in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for entry in contents where entry.hasSuffix(".app") {
                let path = (base as NSString).appendingPathComponent(entry)
                // 只用目录名，不读 Info.plist：减少「访问其他 App 数据」权限提示。
                let name = entry.replacingOccurrences(of: ".app", with: "")
                let match = matchCatalog(name: name, bundleID: nil, index: index)
                results.append(LocalApplication(
                    id: path,
                    name: name,
                    path: path,
                    bundleIdentifier: nil,
                    isInCatalog: match != nil,
                    catalogToolID: match
                ))
            }
        }

        var seen = Set<String>()
        return results
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct CatalogIndex {
        var byName: [String: String] = [:]
        var byBundleID: [String: String] = [:]
    }

    private func buildCatalogIndex(_ catalog: [String: DevTool]) -> CatalogIndex {
        var index = CatalogIndex()
        for tool in catalog.values {
            index.byName[tool.name.lowercased()] = tool.id
            let dashed = tool.id.replacingOccurrences(of: "-", with: " ").lowercased()
            index.byName[dashed] = tool.id
            if tool.source.type == .cask {
                let cask = tool.source.identifier.replacingOccurrences(of: "-", with: " ").lowercased()
                index.byName[cask] = tool.id
            }
            if tool.source.type == .mas || tool.source.identifier.contains(".") {
                index.byBundleID[tool.source.identifier] = tool.id
            }
        }
        return index
    }

    private func matchCatalog(name: String, bundleID: String?, index: CatalogIndex) -> String? {
        let normalized = name.lowercased()
        if let id = index.byName[normalized] { return id }
        if let bundleID, let id = index.byBundleID[bundleID] { return id }
        return nil
    }
}

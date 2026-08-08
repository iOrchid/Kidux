import Foundation

struct FeaturedPickSection: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let toolIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle
        case toolIDs = "tool_ids"
    }
}

private struct FeaturedPicksDocument: Codable {
    let version: Int
    let sections: [FeaturedPickSection]
}

struct ResolvedFeaturedSection: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let tools: [DevTool]
}

enum FeaturedPicksStore {
    static func resolvedSections(catalog: [DevTool]) -> [ResolvedFeaturedSection] {
        let catalogMap = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let document = loadDocument()
        return document.sections.compactMap { section in
            let tools = section.toolIDs.compactMap { catalogMap[$0] }
            guard !tools.isEmpty else { return nil }
            return ResolvedFeaturedSection(
                id: section.id,
                title: section.title,
                subtitle: section.subtitle,
                tools: tools
            )
        }
    }

    static func invalidateCache() {}

    private static func loadDocument() -> FeaturedPicksDocument {
        guard let url = Bundle.main.url(
            forResource: "featured-picks",
            withExtension: "json",
            subdirectory: "bundles"
        ) ?? Bundle.main.url(forResource: "featured-picks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(FeaturedPicksDocument.self, from: data)
        else {
            return FeaturedPicksDocument(version: 1, sections: [])
        }
        return document
    }
}

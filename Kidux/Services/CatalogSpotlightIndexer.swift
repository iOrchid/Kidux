import CoreSpotlight
import Foundation
import AppKit
import UniformTypeIdentifiers

/// S20-01 — 将 Catalog 工具索引到系统 Spotlight
enum CatalogSpotlightIndexer {
    static let domainIdentifier = "co.langem.kidux.catalog"

    static func indexCatalog(_ tools: [DevTool]) {
        let items = tools.map { searchableItem(for: $0) }
        guard !items.isEmpty else { return }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                NSLog("Kidux Spotlight index failed: \(error.localizedDescription)")
            }
        }
    }

    static func deleteAllIndexed() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error {
                NSLog("Kidux Spotlight delete failed: \(error.localizedDescription)")
            }
        }
    }

    static func toolID(from userActivity: NSUserActivity) -> String? {
        userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }

    private static func searchableItem(for tool: DevTool) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = tool.name
        attributes.contentDescription = tool.displayDescription
        attributes.keywords = [tool.category, tool.source.type.rawValue] + (tool.tags ?? [])
        attributes.relatedUniqueIdentifier = tool.id

        let item = CSSearchableItem(
            uniqueIdentifier: tool.id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        return item
    }
}

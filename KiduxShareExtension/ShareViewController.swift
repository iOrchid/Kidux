import AppKit
import UniformTypeIdentifiers

/// S20-05 — 系统分享菜单入口：Brewfile / 快照 JSON / 团队 Bundle → App Group → 打开主 App
final class ShareViewController: NSViewController {
    private var statusLabel: NSTextField!

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        let label = NSTextField(labelWithString: "正在导入到启椟…")
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16)
        ])
        statusLabel = label
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { @MainActor in
            await processIncoming()
        }
    }

    @MainActor
    private func processIncoming() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(message: "没有可导入的内容")
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let text = await loadText(from: provider) {
                    do {
                        let pending = try ShareImportInbox.writePending(
                            fileName: suggestedFileName(for: provider),
                            content: text
                        )
                        statusLabel.stringValue = "已准备导入：\(pending.kind.rawValue)"
                        NSWorkspace.shared.open(ShareImportInbox.openURL)
                        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                        return
                    } catch {
                        finish(message: error.localizedDescription)
                        return
                    }
                }
            }
        }

        finish(message: "未能读取分享内容")
    }

    private func suggestedFileName(for provider: NSItemProvider) -> String {
        if let name = provider.suggestedName, !name.isEmpty { return name }
        if provider.hasItemConformingToTypeIdentifier(UTType.json.identifier) {
            return "shared.json"
        }
        return "Brewfile"
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        let identifiers = [
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
            UTType.json.identifier,
            UTType.fileURL.identifier,
            UTType.data.identifier
        ]

        for typeID in identifiers where provider.hasItemConformingToTypeIdentifier(typeID) {
            if let text = await loadString(provider: provider, typeID: typeID) {
                return text
            }
        }
        return nil
    }

    private func loadString(provider: NSItemProvider, typeID: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                    return
                }
                if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                    return
                }
                if let url = item as? URL, let text = try? String(contentsOf: url, encoding: .utf8) {
                    continuation.resume(returning: text)
                    return
                }
                if let url = item as? NSURL, let text = try? String(contentsOf: url as URL, encoding: .utf8) {
                    continuation.resume(returning: text)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    @MainActor
    private func finish(message: String) {
        statusLabel.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            let error = NSError(
                domain: "co.langem.kidux.share",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            self?.extensionContext?.cancelRequest(withError: error)
        }
    }
}

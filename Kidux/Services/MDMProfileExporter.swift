import Foundation
import AppKit
import OSLog
import UniformTypeIdentifiers

/// S18-13 — 企业 MDM 友好导出（只读 Bundle stub + 本地审计）
enum MDMProfileExporter {
    private static let logger = Logger(subsystem: "co.langem.kidux", category: "mdm-audit")

    struct ExportPayload: Sendable {
        let teamName: String
        let author: String
        let roleIDs: [String]
        let toolIDs: [String]
        let discoverToolIDs: [String]
        let brewMirror: String
        let skipInstalled: Bool
        let readOnly: Bool
        let kiduxVersion: String
        let exportedAt: Date
    }

    enum ExportError: LocalizedError {
        case empty
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .empty: return "请先选择岗位或工具后再导出 MDM 配置"
            case .writeFailed: return "无法写入 .mobileconfig"
            }
        }
    }

    @MainActor
    static func makePayload(from viewModel: AppViewModel) -> ExportPayload {
        ExportPayload(
            teamName: viewModel.settings.teamBundleName,
            author: viewModel.settings.teamBundleAuthor,
            roleIDs: Array(viewModel.selectedRoles).sorted(),
            toolIDs: viewModel.resolvedTools.filter(\.isSelected).map(\.id).sorted(),
            discoverToolIDs: Array(viewModel.discoverSelectedTools).sorted(),
            brewMirror: viewModel.settings.brewMirror.rawValue,
            skipInstalled: viewModel.settings.skipInstalled,
            readOnly: true,
            kiduxVersion: AppInfo.marketingVersion,
            exportedAt: Date()
        )
    }

    static func mobileconfigXML(payload: ExportPayload) throws -> Data {
        guard !payload.roleIDs.isEmpty || !payload.toolIDs.isEmpty || !payload.discoverToolIDs.isEmpty else {
            throw ExportError.empty
        }

        let uuid = UUID().uuidString
        let bundleUUID = UUID().uuidString
        let stamp = ISO8601DateFormatter().string(from: payload.exportedAt)
        let displayName = payload.teamName.isEmpty ? "Kidux Team Bundle" : "Kidux · \(payload.teamName)"

        let kiduxDict: [String: Any] = [
            "Format": "kidux.mdm-bundle",
            "Version": 1,
            "ReadOnly": payload.readOnly,
            "TeamName": payload.teamName,
            "Author": payload.author,
            "RoleIDs": payload.roleIDs,
            "ToolIDs": payload.toolIDs,
            "DiscoverToolIDs": payload.discoverToolIDs,
            "BrewMirror": payload.brewMirror,
            "SkipInstalled": payload.skipInstalled,
            "KiduxVersion": payload.kiduxVersion,
            "ExportedAt": stamp,
            "Note": "Stub profile for Jamf/Kandji packaging. Embed as custom settings; Kidux reads via import JSON equivalent."
        ]

        let kiduxPlist = try PropertyListSerialization.data(
            fromPropertyList: kiduxDict,
            format: .xml,
            options: 0
        )
        guard let kiduxXML = String(data: kiduxPlist, encoding: .utf8)?
            .replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n", with: "")
            .replacingOccurrences(of: "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw ExportError.writeFailed
        }

        // Extract inner <dict>...</dict>
        let inner: String
        if let start = kiduxXML.range(of: "<dict>"),
           let end = kiduxXML.range(of: "</dict>", options: .backwards)
        {
            inner = String(kiduxXML[start.lowerBound..<end.upperBound])
        } else {
            inner = "<dict/>"
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>PayloadContent</key>
          <array>
            <dict>
              <key>PayloadType</key>
              <string>com.apple.ManagedClient.preferences</string>
              <key>PayloadVersion</key>
              <integer>1</integer>
              <key>PayloadIdentifier</key>
              <string>co.langem.kidux.mdm.bundle.\(bundleUUID)</string>
              <key>PayloadUUID</key>
              <string>\(bundleUUID)</string>
              <key>PayloadEnabled</key>
              <true/>
              <key>PayloadDisplayName</key>
              <string>Kidux Read-Only Bundle</string>
              <key>PayloadContent</key>
              <dict>
                <key>co.langem.kidux</key>
                <dict>
                  <key>Forced</key>
                  <array>
                    <dict>
                      <key>mcx_preference_settings</key>
                      \(inner)
                    </dict>
                  </array>
                </dict>
              </dict>
            </dict>
          </array>
          <key>PayloadDisplayName</key>
          <string>\(escapeXML(displayName))</string>
          <key>PayloadIdentifier</key>
          <string>co.langem.kidux.mdm.\(uuid)</string>
          <key>PayloadRemovalDisallowed</key>
          <false/>
          <key>PayloadType</key>
          <string>Configuration</string>
          <key>PayloadUUID</key>
          <string>\(uuid)</string>
          <key>PayloadVersion</key>
          <integer>1</integer>
          <key>PayloadDescription</key>
          <string>Kidux enterprise stub (S18-13). Import team roles/tools as managed preferences.</string>
          <key>PayloadOrganization</key>
          <string>\(escapeXML(payload.author.isEmpty ? "Kidux" : payload.author))</string>
        </dict>
        </plist>
        """

        guard let data = xml.data(using: .utf8) else { throw ExportError.writeFailed }
        return data
    }

    @MainActor
    static func exportPanel(from viewModel: AppViewModel) {
        do {
            let payload = makePayload(from: viewModel)
            let data = try mobileconfigXML(payload: payload)
            let panel = NSSavePanel()
            panel.title = "导出 MDM 配置（stub）"
            let name = payload.teamName.isEmpty ? "Kidux-Team" : payload.teamName
                .replacingOccurrences(of: "/", with: "-")
            panel.nameFieldStringValue = "\(name).mobileconfig"
            panel.allowedContentTypes = [.xml, .propertyList, .data]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            appendAudit(payload: payload, path: url.path)
            EnterpriseAuditStore.shared.record(
                action: "mdm.export",
                detail: url.lastPathComponent,
                toolCount: payload.toolIDs.count,
                source: "settings"
            )
            viewModel.extendedCatalogStatusMessage = "已导出 MDM stub：\(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            viewModel.extendedCatalogStatusMessage = "MDM 导出失败：\(error.localizedDescription)"
        }
    }

    private static func appendAudit(payload: ExportPayload, path: String) {
        let line = "exportedAt=\(ISO8601DateFormatter().string(from: payload.exportedAt)) roles=\(payload.roleIDs.count) tools=\(payload.toolIDs.count) path=\(path)"
        logger.info("MDM export \(line, privacy: .public)")

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("mdm-audit.jsonl")
        let record: [String: Any] = [
            "event": "mdm.export",
            "exportedAt": ISO8601DateFormatter().string(from: payload.exportedAt),
            "roleCount": payload.roleIDs.count,
            "toolCount": payload.toolIDs.count,
            "path": path,
            "readOnly": payload.readOnly
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record),
           var lineData = String(data: data, encoding: .utf8)
        {
            lineData += "\n"
            if let bytes = lineData.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: file.path),
                   let handle = try? FileHandle(forWritingTo: file)
                {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: bytes)
                } else {
                    try? bytes.write(to: file, options: .atomic)
                }
            }
        }
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

import Foundation

enum InstallStatus: String, Sendable {
    case pending
    case running
    case success
    case failed
    case skipped
    case cancelled
}

enum InstallTaskKind: Sendable {
    case tool(ResolvedTool)
    case postInstall(PostInstallStep)
}

struct InstallTask: Identifiable, Sendable {
    let id: String
    let kind: InstallTaskKind
    var status: InstallStatus
    var errorMessage: String?
    var log: String

    var displayName: String {
        switch kind {
        case .tool(let tool):
            return tool.tool.name
        case .postInstall(let step):
            return step.name
        }
    }

    init(tool: ResolvedTool) {
        self.id = "tool-\(tool.id)"
        self.kind = .tool(tool)
        self.status = .pending
        self.errorMessage = nil
        self.log = ""
    }

    init(postInstall step: PostInstallStep) {
        self.id = "post-\(step.id)"
        self.kind = .postInstall(step)
        self.status = .pending
        self.errorMessage = nil
        self.log = ""
    }
}

struct InstallSummary: Sendable {
    let total: Int
    let succeeded: Int
    let failed: Int
    let skipped: Int
}

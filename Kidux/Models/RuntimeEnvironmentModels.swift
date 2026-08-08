import Foundation

enum RuntimeKind: String, CaseIterable, Identifiable, Sendable {
    case node
    case python
    case java
    case go

    var id: String { rawValue }

    var title: String {
        switch self {
        case .node: return "Node.js"
        case .python: return "Python"
        case .java: return "Java"
        case .go: return "Go"
        }
    }

    var icon: String {
        switch self {
        case .node: return "chevron.left.forwardslash.chevron.right"
        case .python: return "terminal"
        case .java: return "cup.and.saucer"
        case .go: return "hare"
        }
    }

    var probeCommand: String {
        switch self {
        case .python: return "python3"
        default: return rawValue
        }
    }

    var versionCommand: String {
        switch self {
        case .node: return "node --version 2>/dev/null"
        case .python: return "python3 --version 2>/dev/null"
        case .java: return "java -version 2>&1 | head -n 1"
        case .go: return "go version 2>/dev/null"
        }
    }
}

struct RuntimeProfile: Identifiable, Sendable, Hashable {
    let kind: RuntimeKind
    let executablePath: String?
    let versionLine: String?

    var id: String { kind.id }

    var isInstalled: Bool { executablePath != nil }

    var displayVersion: String {
        guard let versionLine, !versionLine.isEmpty else { return "—" }
        return versionLine
    }

    var statusLabel: String {
        isInstalled ? "已安装" : "未检测到"
    }
}

enum LocalServiceKind: String, CaseIterable, Identifiable, Sendable {
    case docker
    case mysql
    case redis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docker: return "Docker"
        case .mysql: return "MySQL"
        case .redis: return "Redis"
        }
    }

    var icon: String {
        switch self {
        case .docker: return "shippingbox"
        case .mysql: return "cylinder.split.1x2"
        case .redis: return "memorychip"
        }
    }
}

enum LocalServiceHealthState: String, Sendable {
    case running
    case installed
    case notInstalled
    case unreachable

    var label: String {
        switch self {
        case .running: return "运行中"
        case .installed: return "已安装"
        case .notInstalled: return "未安装"
        case .unreachable: return "不可达"
        }
    }
}

struct LocalServiceHealth: Identifiable, Sendable, Hashable {
    let kind: LocalServiceKind
    let state: LocalServiceHealthState
    let detail: String

    var id: String { kind.id }

    var isHealthy: Bool { state == .running }
}

struct RuntimeEnvironmentSnapshot: Sendable {
    let runtimes: [RuntimeProfile]
    let services: [LocalServiceHealth]
    let brewServices: [BrewServiceItem]
    let versionManagers: [VersionManagerProfile]
    let scannedAt: Date
}

enum VersionManagerKind: String, CaseIterable, Identifiable, Sendable {
    case mise
    case nvm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mise: return "mise"
        case .nvm: return "nvm"
        }
    }

    var icon: String {
        switch self {
        case .mise: return "square.stack.3d.up"
        case .nvm: return "n.square"
        }
    }
}

struct VersionManagerProfile: Identifiable, Sendable, Hashable {
    let kind: VersionManagerKind
    let isInstalled: Bool
    let summaryLine: String
    let detailLines: [String]
    let executablePath: String?

    var id: String { kind.id }

    var statusLabel: String {
        isInstalled ? "已安装" : "未检测到"
    }

    var displaySummary: String {
        guard isInstalled else { return "—" }
        return summaryLine.isEmpty ? "已安装" : summaryLine
    }
}

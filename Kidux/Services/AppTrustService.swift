import Foundation
import AppKit

enum AppTrustIssue: String, Sendable, CaseIterable {
    case quarantine
    case unsigned
    case blocked

    var title: String {
        switch self {
        case .quarantine: return String(localized: "trust.issue.quarantine")
        case .unsigned: return String(localized: "trust.issue.unsigned")
        case .blocked: return String(localized: "trust.issue.blocked")
        }
    }

    var hint: String {
        switch self {
        case .quarantine:
            return String(localized: "trust.issue.quarantine.hint")
        case .unsigned:
            return String(localized: "trust.issue.unsigned.hint")
        case .blocked:
            return String(localized: "trust.issue.blocked.hint")
        }
    }
}

enum AppTrustProbeStatus: String, Sendable {
    case ok
    case needsAttention
    case unknown
}

struct AppTrustReport: Sendable {
    let appPath: String
    let appName: String
    let issues: [AppTrustIssue]
    let quarantineValue: String?
    let assessmentLine: String?
    let probeStatus: AppTrustProbeStatus

    /// 列表与 Sheet 统一：仅隔离或 Gatekeeper 拦截视为可「修复」关注项。
    var needsRepair: Bool {
        issues.contains(.quarantine) || issues.contains(.blocked)
    }

    var needsSystemSettings: Bool {
        issues.contains(.unsigned) || issues.contains(.blocked)
    }

    var summary: String {
        switch probeStatus {
        case .unknown:
            return String(localized: "trust.summary.unknown")
        case .ok where issues.isEmpty:
            return String(localized: "trust.summary.ok")
        default:
            return issues.map(\.title).joined(separator: " · ")
        }
    }
}

enum AppTrustError: LocalizedError {
    case fixFailed(String)

    var errorDescription: String? {
        switch self {
        case .fixFailed(let msg): return msg
        }
    }
}

actor AppTrustService {
    static let shared = AppTrustService()

    private let shell = ShellExecutor()
    private static let probeTimeout: TimeInterval = 5
    private static let cacheTTL: TimeInterval = 60

    private var reportCache: [String: (report: AppTrustReport, cachedAt: Date)] = [:]

    private init() {}

    func cachedNeedsRepair(path: String) -> Bool? {
        guard let entry = reportCache[path],
              Date().timeIntervalSince(entry.cachedAt) < Self.cacheTTL else {
            return nil
        }
        switch entry.report.probeStatus {
        case .unknown:
            return nil
        case .ok:
            return false
        case .needsAttention:
            return entry.report.needsRepair
        }
    }

    func invalidateCache(path: String? = nil) {
        if let path {
            reportCache.removeValue(forKey: path)
        } else {
            reportCache.removeAll()
        }
    }

    func diagnose(appPath: String, force: Bool = false) async -> AppTrustReport {
        if !force,
           let entry = reportCache[appPath],
           Date().timeIntervalSince(entry.cachedAt) < Self.cacheTTL {
            return entry.report
        }

        let name = FileManager.default.displayName(atPath: appPath)
        var issues: [AppTrustIssue] = []
        var quarantineValue: String?
        var assessmentLine: String?
        var xattrSucceeded = false

        do {
            let xattrResult = try await shell.run(
                "xattr -l \"\(appPath)\" 2>/dev/null",
                timeoutSeconds: Self.probeTimeout
            )
            xattrSucceeded = true
            let output = xattrResult.stdout
            if output.contains("com.apple.quarantine") {
                issues.append(.quarantine)
                quarantineValue = output
                    .split(separator: "\n")
                    .first { $0.contains("com.apple.quarantine") }
                    .map(String.init)
            }
        } catch {
            xattrSucceeded = false
        }

        // spctl 仅作辅助；失败不覆盖已确认的 quarantine，也不把失败当成健康。
        do {
            let spctlResult = try await shell.run(
                "spctl -a -vv \"\(appPath)\" 2>&1",
                timeoutSeconds: Self.probeTimeout
            )
            let assessment = spctlResult.combinedOutput
            assessmentLine = assessment.split(separator: "\n").first.map(String.init)

            if assessment.contains("rejected") || assessment.contains("Unnotarized") {
                if !issues.contains(.quarantine) {
                    issues.append(.unsigned)
                }
            }
            if assessment.contains("cannot verify") || assessment.contains("no usable signature") {
                if !issues.contains(.blocked) {
                    issues.append(.blocked)
                }
            }
        } catch {
            // ignore spctl failure when xattr already succeeded
        }

        let probeStatus: AppTrustProbeStatus
        if !xattrSucceeded && issues.isEmpty {
            probeStatus = .unknown
        } else if issues.contains(.quarantine) || issues.contains(.blocked) || issues.contains(.unsigned) {
            probeStatus = .needsAttention
        } else {
            probeStatus = .ok
        }

        let report = AppTrustReport(
            appPath: appPath,
            appName: name,
            issues: issues,
            quarantineValue: quarantineValue,
            assessmentLine: assessmentLine,
            probeStatus: probeStatus
        )
        reportCache[appPath] = (report, Date())
        return report
    }

    func removeQuarantine(appPath: String) async throws {
        let result = try await shell.run(
            "xattr -dr com.apple.quarantine \"\(appPath)\" 2>&1",
            timeoutSeconds: Self.probeTimeout
        )
        guard result.isSuccess else {
            throw AppTrustError.fixFailed(result.combinedOutput)
        }
        invalidateCache(path: appPath)
    }

    func adhocSign(appPath: String) async throws {
        let result = try await shell.run(
            "codesign --force --deep --sign - \"\(appPath)\" 2>&1",
            timeoutSeconds: 30
        )
        guard result.isSuccess else {
            throw AppTrustError.fixFailed(result.combinedOutput)
        }
        invalidateCache(path: appPath)
    }

    @MainActor
    func openPrivacySecuritySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
    }

    @MainActor
    func openGeneralPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?General") {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
    }
}

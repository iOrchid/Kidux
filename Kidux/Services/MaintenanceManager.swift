import Foundation
import Observation

struct MaintenanceTask: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    var status: InstallStatus
    var errorMessage: String?
}

@MainActor
@Observable
final class MaintenanceManager {
    var tasks: [MaintenanceTask] = []
    var logOutput = ""
    var isRunning = false
    var isFinished = false
    var sessionTitle = "维护任务"

    private let shell = ShellExecutor()
    private var homebrew: HomebrewService { HomebrewService(shell: shell) }

    var overallProgress: Double {
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter {
            switch $0.status {
            case .success, .failed, .skipped, .cancelled:
                return true
            case .pending, .running:
                return false
            }
        }.count
        return Double(done) / Double(tasks.count)
    }

    var completedCount: Int { tasks.filter { $0.status == .success }.count }
    var failedCount: Int { tasks.filter { $0.status == .failed }.count }

    func beginUpgradeSession(entries: [OutdatedEntry]) {
        sessionTitle = "批量更新"
        tasks = entries.map {
            MaintenanceTask(
                id: $0.id,
                title: $0.displayName,
                subtitle: $0.sourceLabel,
                status: .pending,
                errorMessage: nil
            )
        }
        logOutput = "⏳ 更新队列已就绪（\(tasks.count) 项）\n"
        isFinished = false
        isRunning = true
    }

    func beginUninstallSession(tools: [DevTool]) {
        sessionTitle = "卸载软件"
        tasks = tools.map { tool in
            MaintenanceTask(
                id: tool.id,
                title: tool.name,
                subtitle: uninstallLabel(for: tool.source),
                status: .pending,
                errorMessage: nil
            )
        }
        logOutput = "⏳ 卸载队列已就绪（\(tasks.count) 项）\n"
        isFinished = false
        isRunning = true
    }

    func beginInstallSession(tools: [DevTool], title: String = "安装软件") {
        sessionTitle = title
        tasks = tools.map { tool in
            MaintenanceTask(
                id: tool.id,
                title: tool.name,
                subtitle: installLabel(for: tool.source),
                status: .pending,
                errorMessage: nil
            )
        }
        logOutput = "⏳ 安装队列已就绪（\(tasks.count) 项）\n"
        isFinished = false
        isRunning = true
    }

    func requestCancel() {
        Task { await shell.cancelActive() }
    }

    func runUpgrades(entries: [OutdatedEntry], mirror: BrewMirror) async {
        isRunning = true
        defer {
            isRunning = false
            isFinished = true
        }

        appendLog("=== 批量更新开始 ===\n")
        for (index, entry) in entries.enumerated() {
            guard tasks.indices.contains(index) else { continue }
            tasks[index].status = .running
            appendLog("▶ \(entry.displayName) (\(entry.sourceLabel))\n")
            do {
                let output = try await UpdateCheckService.upgrade(
                    entry: entry,
                    mirror: mirror,
                    shell: shell
                ) { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line)
                    }
                }
                if !output.isEmpty {
                    appendLog(output + (output.hasSuffix("\n") ? "" : "\n"))
                }
                tasks[index].status = .success
                appendLog("✅ 完成: \(entry.displayName)\n\n")
            } catch {
                tasks[index].status = .failed
                tasks[index].errorMessage = error.localizedDescription
                appendLog("❌ 失败: \(entry.displayName) — \(error.localizedDescription)\n\n")
            }
        }
        appendLog("=== 批量更新结束 · 成功 \(completedCount) · 失败 \(failedCount) ===\n")
    }

    func runUninstalls(tools: [DevTool], mirror: BrewMirror) async {
        isRunning = true
        defer {
            isRunning = false
            isFinished = true
        }

        appendLog("=== 卸载开始 ===\n")
        for (index, tool) in tools.enumerated() {
            guard tasks.indices.contains(index) else { continue }
            tasks[index].status = .running
            appendLog("▶ 卸载 \(tool.name) (\(tool.source.identifier))\n")
            do {
                let output = try await UpdateCheckService.uninstall(
                    tool: tool,
                    mirror: mirror,
                    shell: shell
                ) { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line)
                    }
                }
                if !output.isEmpty {
                    appendLog(output + (output.hasSuffix("\n") ? "" : "\n"))
                }
                tasks[index].status = .success
                appendLog("✅ 已卸载: \(tool.name)\n\n")
            } catch {
                tasks[index].status = .failed
                tasks[index].errorMessage = error.localizedDescription
                appendLog("❌ 卸载失败: \(tool.name) — \(error.localizedDescription)\n\n")
            }
        }
        appendLog("=== 卸载结束 · 成功 \(completedCount) · 失败 \(failedCount) ===\n")
    }

    func runInstalls(tools: [DevTool], mirror: BrewMirror) async {
        isRunning = true
        defer {
            isRunning = false
            isFinished = true
        }

        appendLog("=== 安装开始 ===\n")
        for (index, tool) in tools.enumerated() {
            guard tasks.indices.contains(index) else { continue }
            tasks[index].status = .running
            appendLog("▶ 安装 \(tool.name) (\(tool.source.identifier))\n")
            do {
                let output = try await homebrew.installTool(tool, mirror: mirror) { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line)
                    }
                }
                if !output.isEmpty {
                    appendLog(output + (output.hasSuffix("\n") ? "" : "\n"))
                }
                tasks[index].status = .success
                appendLog("✅ 已安装: \(tool.name)\n\n")
            } catch let error as ShellError {
                if case .cancelled = error {
                    tasks[index].status = .cancelled
                    tasks[index].errorMessage = "已取消"
                    appendLog("⏹ 已取消: \(tool.name)\n\n")
                    for cancelIndex in (index + 1)..<tasks.count {
                        tasks[cancelIndex].status = .cancelled
                    }
                    appendLog("=== 安装已取消 ===\n")
                    return
                }
                tasks[index].status = .failed
                tasks[index].errorMessage = error.localizedDescription
                appendLog("❌ 安装失败: \(tool.name) — \(error.localizedDescription)\n\n")
            } catch {
                tasks[index].status = .failed
                tasks[index].errorMessage = error.localizedDescription
                appendLog("❌ 安装失败: \(tool.name) — \(error.localizedDescription)\n\n")
            }
        }
        appendLog("=== 安装结束 · 成功 \(completedCount) · 失败 \(failedCount) ===\n")
    }

    private let maxLogCharacters = 120_000
    private var pendingLog = ""
    private var logFlushTask: Task<Void, Never>?

    private func appendLog(_ text: String) {
        pendingLog += text
        if logFlushTask == nil {
            logFlushTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                flushPendingLog()
            }
        }
    }

    private func flushPendingLog() {
        logFlushTask = nil
        guard !pendingLog.isEmpty else { return }
        logOutput += pendingLog
        pendingLog = ""
        if logOutput.count > maxLogCharacters {
            logOutput = String(logOutput.suffix(maxLogCharacters))
        }
    }

    private func uninstallLabel(for source: InstallSource) -> String {
        switch source.type {
        case .formula: return "brew formula · \(source.identifier)"
        case .cask: return "brew cask · \(source.identifier)"
        default: return source.identifier
        }
    }

    private func installLabel(for source: InstallSource) -> String {
        switch source.type {
        case .formula: return "brew install \(source.identifier)"
        case .cask: return "brew install --cask \(source.identifier)"
        case .mas: return "mas install \(source.identifier)"
        case .script: return "脚本"
        case .link: return "外链"
        }
    }
}

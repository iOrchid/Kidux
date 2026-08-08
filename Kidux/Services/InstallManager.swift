import Foundation
import Observation

@MainActor
@Observable
final class InstallManager {
    var tasks: [InstallTask] = []
    var currentTaskID: String?
    var logOutput: String = ""
    var isInstalling = false
    var isFinished = false
    var isCancelled = false
    var summary: InstallSummary?

    private let shell = ShellExecutor()
    private let homebrew: HomebrewService
    private let mas: MASService
    private let scriptRunner: ScriptRunner

    init() {
        homebrew = HomebrewService(shell: shell)
        mas = MASService(shell: shell)
        scriptRunner = ScriptRunner(shell: shell)
    }

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

    var currentTask: InstallTask? {
        guard let id = currentTaskID else { return nil }
        return tasks.first { $0.id == id }
    }

    var completedCount: Int {
        tasks.filter { $0.status == .success }.count
    }

    var failedCount: Int {
        tasks.filter { $0.status == .failed }.count
    }

    var pendingCount: Int {
        tasks.filter { $0.status == .pending }.count
    }

    /// 日志中出现 sudo / Password 提示时，引导用户在终端授权
    var awaitingAdminPassword: Bool {
        let tail = String(logOutput.suffix(1200)).lowercased()
        return tail.contains("password:") || tail.contains("password for") || tail.contains("sudo:")
    }

    func prepare(tools: [ResolvedTool], postInstallSteps: [PostInstallStep]) {
        var queue: [InstallTask] = tools
            .filter(\.isSelected)
            .map { InstallTask(tool: $0) }
        queue.append(contentsOf: postInstallSteps.map { InstallTask(postInstall: $0) })
        tasks = queue
        logOutput = "⏳ 安装队列已就绪，等待开始…\n"
        isFinished = false
        isCancelled = false
        isInstalling = false
        summary = nil
    }

    /// 发现页等场景：先展示 Sheet 再执行安装，避免 UI 不刷新
    func beginInteractiveSession(
        tools: [ResolvedTool],
        postInstallSteps: [PostInstallStep]
    ) {
        prepare(tools: tools, postInstallSteps: postInstallSteps)
        isInstalling = true
    }

    func startInstallation(
        tools: [ResolvedTool],
        postInstallSteps: [PostInstallStep],
        mirror: BrewMirror,
        enableMAS: Bool,
        skipInstalled: Bool,
        snapshot: InstalledStatusSnapshot?
    ) async {
        let shouldPrepare = tasks.isEmpty || !isInstalling
        if shouldPrepare {
            prepare(tools: tools, postInstallSteps: postInstallSteps)
        }
        isInstalling = true
        await shell.resetCancellation()
        defer { isInstalling = false }

        appendLog("=== \(BrandInfo.displayNameCN) 安装开始 ===\n")
        appendLog("镜像源: \(mirror.displayName)\n\n")

        if await !homebrew.isInstalled() {
            appendLog("正在安装 Homebrew...\n")
            appendLog("💡 若弹出密码框，请在系统对话框中输入 Mac 登录密码\n")
            do {
                try await homebrew.installHomebrew(mirror: mirror) { text in
                    Task { @MainActor in self.appendLog(text) }
                }
                appendLog("Homebrew 安装完成\n")
            } catch {
                if handleCancellation(error) { return }
                appendLog("Homebrew 安装失败: \(error.localizedDescription)\n")
                markAllFailed(error.localizedDescription)
                finish()
                return
            }
        } else {
            appendLog("Homebrew 已安装\n")
            if mirror != .official {
                appendLog("正在配置镜像源...\n")
                try? await homebrew.applyMirrorRemotes(mirror: mirror) { text in
                    Task { @MainActor in self.appendLog(text) }
                }
            }
        }

        if enableMAS {
            appendLog("检查 mas-cli...\n")
            try? await homebrew.ensureMASInstalled(mirror: mirror) { text in
                Task { @MainActor in self.appendLog(text) }
            }
        }

        await executeTaskQueue(
            mirror: mirror,
            enableMAS: enableMAS,
            skipInstalled: skipInstalled,
            snapshot: snapshot
        )
    }

    /// 从失败 / 取消项继续安装（S13-06）
    func resumeInstallation(
        mirror: BrewMirror,
        enableMAS: Bool,
        skipInstalled: Bool,
        snapshot: InstalledStatusSnapshot?
    ) async {
        guard canResumeInstallation else { return }

        resetTasksForResume()
        isFinished = false
        isCancelled = false
        isInstalling = true
        await shell.resetCancellation()
        defer { isInstalling = false }

        let pending = tasks.filter { $0.status == .pending }.count
        appendLog("\n=== 从断点继续安装（\(pending) 项待处理）===\n")

        await executeTaskQueue(
            mirror: mirror,
            enableMAS: enableMAS,
            skipInstalled: skipInstalled,
            snapshot: snapshot
        )
    }

    var resumableTaskCount: Int {
        tasks.filter { $0.status == .failed || $0.status == .cancelled }.count
    }

    var canResumeInstallation: Bool {
        (isFinished || isCancelled) && resumableTaskCount > 0
    }

    private func resetTasksForResume() {
        for index in tasks.indices {
            switch tasks[index].status {
            case .failed, .cancelled:
                tasks[index].status = .pending
                tasks[index].errorMessage = nil
            case .running:
                tasks[index].status = .pending
            default:
                break
            }
        }
    }

    private func executeTaskQueue(
        mirror: BrewMirror,
        enableMAS: Bool,
        skipInstalled: Bool,
        snapshot: InstalledStatusSnapshot?
    ) async {
        for index in tasks.indices {
            if isCancelled { break }
            guard tasks[index].status == .pending else { continue }

            currentTaskID = tasks[index].id
            tasks[index].status = .running

            switch tasks[index].kind {
            case .tool(let resolved):
                await installTool(
                    at: index,
                    resolved: resolved,
                    mirror: mirror,
                    enableMAS: enableMAS,
                    skipInstalled: skipInstalled,
                    snapshot: snapshot
                )
            case .postInstall(let step):
                await runPostInstall(at: index, step: step, mirror: mirror)
            }

            if isCancelled { break }
        }

        markRemainingCancelled()
        currentTaskID = nil
        finish()
    }

    func requestCancel() async {
        guard isInstalling else { return }
        isCancelled = true
        appendLog("\n⏹ 正在停止当前安装任务…\n")
        await shell.cancelActive()
    }

    func skipRemainingTasks() {
        for index in tasks.indices where tasks[index].status == .pending {
            tasks[index].status = .skipped
            appendLog("⏭ 已跳过: \(tasks[index].displayName)\n")
        }
        recalculateSummary()
    }

    private func installTool(
        at index: Int,
        resolved: ResolvedTool,
        mirror: BrewMirror,
        enableMAS: Bool,
        skipInstalled: Bool,
        snapshot: InstalledStatusSnapshot?
    ) async {
        let tool = resolved.tool

        if tool.source.type == .mas, !enableMAS {
            tasks[index].status = .skipped
            appendLog("⏭ 跳过（未启用 App Store 集成）: \(tool.name)\n")
            return
        }

        if skipInstalled, await isAlreadyInstalled(tool: tool, snapshot: snapshot) {
            tasks[index].status = .skipped
            appendLog("⏭ 跳过（已安装）: \(tool.name)\n")
            return
        }

        appendLog("📦 正在安装: \(tool.name)...\n")
        if tool.source.type == .formula || tool.source.type == .cask {
            appendLog("💡 部分 brew 包需要管理员权限，若系统弹出密码框请输入 Mac 登录密码\n")
        }

        do {
            let output: String
            switch tool.source.type {
            case .mas:
                output = try await mas.install(
                    appID: tool.source.identifier,
                    environment: mirror.environmentVariables
                ) { text in
                    Task { @MainActor in self.appendLog(text) }
                }
            case .script:
                output = try await scriptRunner.runBundledScript(
                    named: tool.source.identifier,
                    environment: mirror.environmentVariables
                ) { text in
                    Task { @MainActor in self.appendLog(text) }
                }
            case .formula, .cask:
                output = try await installBrewWithRetry(
                    tool: tool,
                    mirror: mirror,
                    taskIndex: index
                )
            case .link:
                tasks[index].status = .skipped
                appendLog("⏭ 外链软件请手动安装: \(tool.name)\n")
                return
            }
            if isCancelled {
                tasks[index].status = .cancelled
                return
            }
            tasks[index].status = .success
            tasks[index].log = output
            appendLog("✅ 完成: \(tool.name)\n")
        } catch {
            if handleCancellation(error) {
                tasks[index].status = .cancelled
                return
            }
            tasks[index].status = .failed
            tasks[index].errorMessage = error.localizedDescription
            appendLog("❌ 失败: \(tool.name) — \(error.localizedDescription)\n")
        }
    }

    private func runPostInstall(
        at index: Int,
        step: PostInstallStep,
        mirror: BrewMirror
    ) async {
        if await scriptRunner.shouldSkip(condition: step.skipIf) {
            tasks[index].status = .skipped
            appendLog("⏭ 跳过（条件满足）: \(step.name)\n")
            return
        }

        appendLog("⚙️ 正在配置: \(step.name)...\n")
        do {
            let output = try await scriptRunner.runBundledScript(
                named: step.script,
                environment: mirror.environmentVariables
                    .merging(ShellPreferenceService.scriptEnvironment(preferred: AppSettings.shared.preferredShell)) { _, new in new }
            ) { text in
                Task { @MainActor in self.appendLog(text) }
            }
            if isCancelled {
                tasks[index].status = .cancelled
                return
            }
            tasks[index].status = .success
            tasks[index].log = output
            appendLog("✅ 完成: \(step.name)\n")
        } catch {
            if handleCancellation(error) {
                tasks[index].status = .cancelled
                return
            }
            tasks[index].status = .failed
            tasks[index].errorMessage = error.localizedDescription
            appendLog("❌ 失败: \(step.name) — \(error.localizedDescription)\n")
        }
    }

    private func installBrewWithRetry(
        tool: DevTool,
        mirror: BrewMirror,
        taskIndex: Int
    ) async throws -> String {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try await homebrew.installTool(tool, mirror: mirror) { text in
                    Task { @MainActor in self.appendLog(text) }
                }
            } catch {
                lastError = error
                if handleCancellation(error) { throw error }
                guard attempt < 3, isRetryableNetworkError(error) else { throw error }
                appendLog("⚠️ 网络异常，\(attempt * 2) 秒后重试（\(attempt)/3）…\n")
                try await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
            }
        }
        throw lastError ?? HomebrewError.commandFailed("安装失败")
    }

    private func isRetryableNetworkError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("network")
            || msg.contains("timeout")
            || msg.contains("timed out")
            || msg.contains("could not resolve")
            || msg.contains("connection")
            || msg.contains("failed to download")
    }

    private func isAlreadyInstalled(tool: DevTool, snapshot: InstalledStatusSnapshot?) async -> Bool {
        switch tool.source.type {
        case .mas:
            return await mas.isAppInstalled(appID: tool.source.identifier)
        case .script:
            return await scriptRunner.shouldSkip(condition: tool.source.skipIf)
        case .formula, .cask:
            return await homebrew.isToolInstalled(tool, snapshot: snapshot)
        case .link:
            return false
        }
    }

    func retryTask(
        _ taskID: String,
        mirror: BrewMirror,
        enableMAS: Bool
    ) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        isInstalling = true
        isCancelled = false
        await shell.resetCancellation()
        defer { isInstalling = false }

        tasks[index].status = .running
        tasks[index].errorMessage = nil
        currentTaskID = taskID

        switch tasks[index].kind {
        case .tool(let resolved):
            await installTool(
                at: index,
                resolved: resolved,
                mirror: mirror,
                enableMAS: enableMAS,
                skipInstalled: false,
                snapshot: nil
            )
        case .postInstall(let step):
            await runPostInstall(at: index, step: step, mirror: mirror)
        }

        currentTaskID = nil
        recalculateSummary()
    }

    @discardableResult
    private func handleCancellation(_ error: Error) -> Bool {
        if case ShellError.cancelled = error {
            isCancelled = true
            return true
        }
        return isCancelled
    }

    private func markRemainingCancelled() {
        for index in tasks.indices {
            switch tasks[index].status {
            case .pending:
                tasks[index].status = isCancelled ? .cancelled : tasks[index].status
            case .running where isCancelled:
                tasks[index].status = .cancelled
            default:
                break
            }
        }
        if isCancelled {
            appendLog("\n=== 安装已停止 ===\n")
        }
    }

    private func finish() {
        isFinished = true
        recalculateSummary()
        if !isCancelled {
            appendLog("\n=== 安装完成 ===\n")
        }
    }

    private func recalculateSummary() {
        let succeeded = tasks.filter { $0.status == .success }.count
        let failed = tasks.filter { $0.status == .failed }.count
        let skipped = tasks.filter { $0.status == .skipped }.count
        summary = InstallSummary(
            total: tasks.count,
            succeeded: succeeded,
            failed: failed,
            skipped: skipped
        )
    }

    private func markAllFailed(_ message: String) {
        for index in tasks.indices {
            tasks[index].status = .failed
            tasks[index].errorMessage = message
        }
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
}

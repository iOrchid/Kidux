import Foundation
import Darwin

/// 登记所有 shell `Process`，供退出时统一取消（含进程组）。
actor ShellProcessRegistry {
    static let shared = ShellProcessRegistry()

    private var processes: [ObjectIdentifier: Process] = [:]

    func register(_ process: Process) {
        processes[ObjectIdentifier(process)] = process
    }

    func unregister(_ process: Process) {
        processes.removeValue(forKey: ObjectIdentifier(process))
    }

    /// 向所有活动进程发 SIGINT → 等待 → SIGTERM → `terminate()`，并清理登记表。
    func cancelAll(graceSeconds: Double = 1.5) async {
        let snapshot = Array(processes.values)
        for process in snapshot {
            Self.signalProcessGroup(process, signal: SIGINT)
        }
        try? await Task.sleep(for: .seconds(graceSeconds))
        for process in snapshot where process.isRunning {
            Self.signalProcessGroup(process, signal: SIGTERM)
            process.terminate()
        }
        processes.removeAll()
    }

    var activeCount: Int { processes.count }

    private static func signalProcessGroup(_ process: Process, signal: Int32) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        kill(-pid, signal)
        kill(pid, signal)
    }
}

struct ShellResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool { exitCode == 0 }
    var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum ShellError: LocalizedError {
    case commandFailed(exitCode: Int32, output: String)
    case executableNotFound(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let output):
            return "命令退出码 \(code): \(output)"
        case .executableNotFound(let path):
            return "找不到可执行文件: \(path)"
        case .cancelled:
            return "命令已取消"
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private let maxBytes = 512_000

    func appendStdout(_ data: Data) {
        lock.withLock { append(&stdout, data) }
    }

    func appendStderr(_ data: Data) {
        lock.withLock { append(&stderr, data) }
    }

    func snapshot() -> (stdout: String, stderr: String) {
        lock.withLock {
            (
                String(data: stdout, encoding: .utf8) ?? "",
                String(data: stderr, encoding: .utf8) ?? ""
            )
        }
    }

    private func append(_ buffer: inout Data, _ data: Data) {
        buffer.append(data)
        if buffer.count > maxBytes {
            buffer = buffer.suffix(maxBytes)
        }
    }
}

actor ShellExecutor {
    private var activeProcess: Process?
    private var cancelRequested = false

    var hasActiveProcess: Bool { activeProcess != nil }

    func cancelActive() {
        cancelRequested = true
        guard let process = activeProcess else { return }
        let pid = process.processIdentifier
        if pid > 0 {
            kill(-pid, SIGINT)
            kill(pid, SIGINT)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if process.isRunning {
                if pid > 0 {
                    kill(-pid, SIGTERM)
                    kill(pid, SIGTERM)
                }
                process.terminate()
            }
        }
    }

    func resetCancellation() {
        cancelRequested = false
    }

    func run(
        _ command: String,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let collector = OutputCollector()

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", command]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            process.environment = env

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                collector.appendStdout(data)
                if let text = String(data: data, encoding: .utf8) {
                    onOutput?(text)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                collector.appendStderr(data)
                if let text = String(data: data, encoding: .utf8) {
                    onOutput?(text)
                }
            }

            process.terminationHandler = { [weak self] proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let (stdout, stderr) = collector.snapshot()
                let result = ShellResult(
                    exitCode: proc.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )

                Task {
                    await ShellProcessRegistry.shared.unregister(proc)
                    await self?.clearActiveProcess()
                    let wasCancelled = await self?.cancelRequested == true
                    if wasCancelled {
                        continuation.resume(throwing: ShellError.cancelled)
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }

            activeProcess = process

            do {
                try process.run()
                if process.processIdentifier > 0 {
                    setpgid(process.processIdentifier, process.processIdentifier)
                }
                Task { await ShellProcessRegistry.shared.register(process) }
                if let timeoutSeconds, timeoutSeconds > 0 {
                    let deadline = timeoutSeconds
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(deadline))
                        guard let self else { return }
                        let active = await self.activeProcess
                        if active === process, process.isRunning {
                            await self.cancelActive()
                        }
                    }
                }
            } catch {
                activeProcess = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func clearActiveProcess() {
        activeProcess = nil
        cancelRequested = false
    }
}

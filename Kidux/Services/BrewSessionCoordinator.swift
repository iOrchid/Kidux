import Foundation

/// S22-11 — Homebrew / mas 全局互斥与单飞扫描，避免并发 brew 锁库。
actor BrewSessionCoordinator {
    static let shared = BrewSessionCoordinator()

    private var exclusiveCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private var cachedInstalled: InstalledStatusSnapshot?
    private var installedTask: Task<InstalledStatusSnapshot, Never>?
    private var outdatedTask: Task<OutdatedScanResponse, Never>?

    func withExclusive<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquireExclusive()
        defer { releaseExclusive() }
        return try await operation()
    }

    func installedSnapshot(
        force: Bool,
        scan: @Sendable @escaping () async -> InstalledStatusSnapshot
    ) async -> InstalledStatusSnapshot {
        if !force, let cachedInstalled { return cachedInstalled }
        if let installedTask {
            return await installedTask.value
        }
        let task = Task {
            await withExclusive {
                await scan()
            }
        }
        installedTask = task
        let value = await task.value
        cachedInstalled = value
        installedTask = nil
        return value
    }

    func outdatedScan(
        force: Bool,
        scan: @Sendable @escaping () async -> OutdatedScanResponse
    ) async -> OutdatedScanResponse {
        if let outdatedTask, !force {
            return await outdatedTask.value
        }
        let task = Task {
            await withExclusive {
                await scan()
            }
        }
        outdatedTask = task
        let value = await task.value
        outdatedTask = nil
        return value
    }

    func invalidateCaches() {
        cachedInstalled = nil
    }

    private func acquireExclusive() async {
        if exclusiveCount == 0 {
            exclusiveCount = 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        exclusiveCount = 1
    }

    private func releaseExclusive() {
        exclusiveCount = 0
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.resume()
    }
}

import Foundation
import os

/// 以仓库为粒度的 libgit2 执行队列池。
///
/// ## 为什么需要它
///
/// libgit2 以 `GIT_THREADS` 构建后，保证的是"**不同对象**可以在不同线程使用"，
/// 但**同一仓库的并发操作存在已知竞态**，历史上曾导致宿主进程内存破坏
/// （`EXC_BREAKPOINT` / `pthread_self` PAC 校验失败）。
///
/// 早期实现用一个**进程级串行队列**规避该问题，代价是：任何一次慢调用
/// （超大仓库的 status / diff）都会阻塞进程中**所有**仓库的 Git 操作。对
/// GitOK 这种"频繁切换项目"的场景，这会造成新项目刷新被旧项目扫描挡住，
/// 也是当时把读数路径退回 CLI 的根本原因。
///
/// 本实现把串行粒度从"进程"收敛到"仓库"：
///
/// - **同一仓库**：串行执行，保证竞态安全。
/// - **不同仓库**：并行执行，互不阻塞。
///
/// ## 重入语义
///
/// 库内部存在公开 API 互相调用的情况（例如 `pull` 内部调用 `hasUncommittedChanges`、
/// `getCurrentBranch`）。为避免嵌套 `sync` 造成死锁，队列池用 `DispatchSpecificKey`
/// 记录"当前线程正在哪个仓库队列上"：
///
/// - 已在**同一仓库**队列上 → 直接执行（真正的重入）。
/// - 在**其他仓库**队列上 → 切换到目标仓库队列（跨仓库嵌套极少见，见下方约束）。
/// - 不在任何仓库队列上 → 调度到目标仓库队列。
///
/// ## 约束
///
/// 不应对**两个不同仓库**做相互嵌套的同步调用并形成环（A 等 B、B 等 A），
/// 否则会死锁。当前库内所有操作都是单仓库语义，不存在该模式。
public final class LibGit2QueuePool: @unchecked Sendable {
    public static let shared = LibGit2QueuePool()

    /// 单个条目：目标队列 + 在途任务计数 + 最近使用时间。
    private struct Entry {
        let queue: DispatchQueue
        var inFlight: Int
        var lastUsed: Date
    }

    /// 无仓库语义操作（初始化、版本号、全局配置）使用的队列。
    private let globalQueue: DispatchQueue

    /// 当前线程所在仓库队列的 key（值为规范化后的仓库路径）。
    private let repositorySpecificKey = DispatchSpecificKey<String>()

    /// 当前线程是否位于全局队列。
    private let globalSpecificKey = DispatchSpecificKey<Void>()

    private let lock = OSAllocatedUnfairLock(initialState: [String: Entry]())

    /// 空闲条目超过该数量时触发回收，避免长时间运行后条目无限增长。
    private let idleEvictionThreshold = 256

    private init() {
        globalQueue = DispatchQueue(
            label: "com.coffic.libgit2.execution.global",
            qos: .userInitiated
        )
        globalQueue.setSpecific(key: globalSpecificKey, value: ())
    }

    // MARK: - 公开入口

    /// 在指定仓库的执行队列上运行 `body`。
    ///
    /// - Parameter repositoryPath: 仓库路径；传 `nil` 表示无仓库语义的全局操作。
    func sync<T>(repositoryPath: String?, _ body: () throws -> T) rethrows -> T {
        guard let repositoryPath else {
            return try syncGlobal(body)
        }

        let key = Self.normalize(repositoryPath)
        let queue = acquireQueue(for: key)

        defer { releaseQueue(for: key) }

        // 真正的重入：当前线程已经在同一仓库队列上。
        if DispatchQueue.getSpecific(key: repositorySpecificKey) == key {
            return try body()
        }

        return try queue.sync(execute: body)
    }

    /// 重置队列池（仅供测试使用）。
    func reset() {
        lock.withLock { $0.removeAll() }
    }

    // MARK: - 内部实现

    private func syncGlobal<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: globalSpecificKey) != nil {
            return try body()
        }
        return try globalQueue.sync(execute: body)
    }

    /// 取得目标仓库队列并登记一次在途任务（同一步锁内完成，保证条目有效）。
    private func acquireQueue(for key: String) -> DispatchQueue {
        lock.withLock { entries in
            if var entry = entries[key] {
                entry.inFlight += 1
                entry.lastUsed = Date()
                entries[key] = entry
                return entry.queue
            }

            evictIdleEntriesIfNeeded(&entries)

            let queue = DispatchQueue(
                label: "com.coffic.libgit2.execution.repo.\(key)",
                qos: .userInitiated
            )
            queue.setSpecific(key: repositorySpecificKey, value: key)
            entries[key] = Entry(queue: queue, inFlight: 1, lastUsed: Date())
            return queue
        }
    }

    /// 释放在途任务计数（必须与 `acquireQueue` 配对）。
    private func releaseQueue(for key: String) {
        lock.withLock { entries in
            guard var entry = entries[key] else { return }
            entry.inFlight = max(0, entry.inFlight - 1)
            entry.lastUsed = Date()
            entries[key] = entry
        }
    }

    /// 只回收**空闲**条目（`inFlight == 0`），避免丢弃仍在执行的队列导致
    /// 同一仓库出现两个队列、失去互斥保证。
    private func evictIdleEntriesIfNeeded(_ entries: inout [String: Entry]) {
        guard entries.count > idleEvictionThreshold else { return }

        let idleKeys = entries
            .filter { $0.value.inFlight == 0 }
            .sorted { $0.value.lastUsed < $1.value.lastUsed }
            .prefix(entries.count - idleEvictionThreshold)
            .map(\.key)

        for key in idleKeys {
            entries.removeValue(forKey: key)
        }
    }

    /// 规范化仓库路径，使同一仓库的不同写法映射到同一队列。
    ///
    /// 解析符号链接并标准化 `..` / `.`，避免 `/repo` 与 `/repo/subdir/..`
    /// 被当成两个不同仓库而失去互斥。
    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}

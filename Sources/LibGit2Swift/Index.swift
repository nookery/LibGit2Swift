import Clibgit2
import Foundation
import OSLog

/// 读取 git index（暂存区）内容的操作。
extension LibGit2 {
    /// 返回当前记录在 git index 中的全部文件路径。
    ///
    /// 等价于 `git ls-files`：路径使用正斜杠分隔、相对仓库根目录。
    ///
    /// 与 `getTrackedFilePaths(at:)`（读取 HEAD 树）不同，本方法反映的是
    /// **暂存区**视角，因此包含尚未提交的新增文件、已暂存删除但仍存在于
    /// HEAD 的文件，以及暂存的重命名目标路径。
    ///
    /// 冲突文件在 index 中最多存在 stage 1/2/3 三个条目，本方法按路径去重，
    /// 与 `git ls-files` 的输出一致。
    ///
    /// - Parameters:
    ///   - path: 仓库路径。
    ///   - cancellation: 可选的取消令牌；取消时抛出 `CancellationError`。
    /// - Returns: 相对仓库根目录的路径列表，顺序与 index 中的记录顺序一致。
    /// - Throws: `LibGit2Error.cannotGetIndex` 当仓库无法打开或 index 无法读取；
    ///           `CancellationError` 当操作被取消。
    public static func getIndexEntries(
        at path: String,
        cancellation: GitCancellationToken? = nil
    ) throws -> [String] {
        if let cancellation {
            return try LibGit2.serialized(at: path, cancellation: cancellation) {
                try getIndexEntriesUnlocked(at: path, cancellation: cancellation)
            }
        }

        return try LibGit2.serialized(at: path) {
            try getIndexEntriesUnlocked(at: path, cancellation: nil)
        }
    }

    // MARK: - 私有方法

    private static func getIndexEntriesUnlocked(
        at path: String,
        cancellation: GitCancellationToken?
    ) throws -> [String] {
        try checkCancellation(cancellation)

        let repo = try openRepositoryUnlocked(at: path)
        defer { git_repository_free(repo) }

        var index: OpaquePointer?
        guard git_repository_index(&index, repo) == 0, let index else {
            throw LibGit2Error.cannotGetIndex
        }
        defer { git_index_free(index) }

        let count = git_index_entrycount(index)
        var paths: [String] = []
        var seen = Set<String>()
        paths.reserveCapacity(count)

        for offset in 0..<count {
            try checkCancellation(cancellation)
            guard let entry = git_index_get_byindex(index, offset),
                  let pathPointer = entry.pointee.path else {
                continue
            }
            let entryPath = String(cString: pathPointer)
            // 冲突文件在 index 中按 stage 重复出现，去重后与 `git ls-files` 一致。
            if seen.insert(entryPath).inserted {
                paths.append(entryPath)
            }
        }

        return paths
    }
}

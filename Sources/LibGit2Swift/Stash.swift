import Foundation
import Clibgit2
import OSLog

private final class StashListPayload {
    var stashes: [(index: Int, message: String, commitHash: String)] = []
}

/// LibGit2 暂存操作扩展
extension LibGit2 {
    /// 暂存当前变更
    /// - Parameters:
    ///   - message: 暂存信息（可选）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    /// - Returns: 暂存索引
    static func stash(message: String? = nil, at path: String, verbose: Bool = true) throws -> Int {
        if verbose { os_log("🐚 LibGit2: Stashing changes") }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 创建签名
        let signature = try createSignature(at: path, verbose: verbose)
        defer { git_signature_free(signature) }

        var commitOID = git_oid()

        let result = git_stash_save(
            &commitOID,
            repo,
            signature,
            message ?? "WIP",
            UInt32(GIT_STASH_INCLUDE_UNTRACKED.rawValue)
        )

        if result == GIT_ENOTFOUND.rawValue {
            if verbose { os_log("🐚 LibGit2: No changes to stash") }
            return -1
        }

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        if verbose { os_log("🐚 LibGit2: Changes stashed at index: 0") }

        return 0
    }

    /// 恢复暂存的变更
    /// - Parameters:
    ///   - index: 暂存索引（默认 0，即最近的 stash）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func stashPop(index: Int = 0, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Popping stash at index: %d", index) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var stashOpts = git_stash_apply_options()
        git_stash_apply_init_options(&stashOpts, UInt32(GIT_STASH_APPLY_OPTIONS_VERSION))

        let result = git_stash_pop(repo, index, &stashOpts)

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        if verbose { os_log("🐚 LibGit2: Stash popped successfully") }
    }

    /// 应用暂存的变更（不从 stash 列表中删除）
    /// - Parameters:
    ///   - index: 暂存索引（默认 0，即最近的 stash）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func stashApply(index: Int = 0, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Applying stash at index: %d", index) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var stashOpts = git_stash_apply_options()
        git_stash_apply_init_options(&stashOpts, UInt32(GIT_STASH_APPLY_OPTIONS_VERSION))
        
        stashOpts.checkout_options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        let result = git_stash_apply(repo, index, &stashOpts)

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        if verbose { os_log("🐚 LibGit2: Stash applied successfully") }
    }

    /// 获取暂存列表
    /// - Parameter path: 仓库路径
    /// - Returns: 暂存信息列表
    static func getStashList(at path: String) throws -> [(index: Int, message: String, commitHash: String)] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let payload = StashListPayload()
        let payloadPointer = Unmanaged.passUnretained(payload).toOpaque()

        let result = git_stash_foreach(repo, { index, message, stashID, payload in
            guard let payload else { return -1 }

            let box = Unmanaged<StashListPayload>.fromOpaque(payload).takeUnretainedValue()
            let stashMessage = message.map { String(cString: $0) } ?? ""
            let shortMessage = stashMessage.components(separatedBy: "\n").first ?? stashMessage
            let commitHash = stashID.map { LibGit2.oidToString($0.pointee) } ?? ""
            box.stashes.append((index: Int(index), message: shortMessage, commitHash: commitHash))
            return 0
        }, payloadPointer)

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        return payload.stashes
    }

    /// 删除暂存
    /// - Parameters:
    ///   - index: 暂存索引（默认 0，即最近的 stash）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func stashDrop(index: Int = 0, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Dropping stash at index: %d", index) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let result = git_stash_drop(repo, index)

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        if verbose { os_log("🐚 LibGit2: Stash dropped successfully") }
    }

    /// 清空所有暂存
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func stashClear(at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Clearing all stashes") }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let count = try getStashCount(at: path)

        // 从后往前删除，避免索引问题
        for i in stride(from: count - 1, through: 0, by: -1) {
            git_stash_drop(repo, i)
        }

        if verbose { os_log("🐚 LibGit2: All stashes cleared") }
    }

    /// 获取暂存数量
    /// - Parameter path: 仓库路径
    /// - Returns: 暂存数量
    static func getStashCount(at path: String) throws -> Int {
        let stashes = try getStashList(at: path)
        return stashes.count
    }

    /// 检查是否有暂存
    /// - Parameter path: 仓库路径
    /// - Returns: 如果有暂存返回 true
    static func hasStash(at path: String) throws -> Bool {
        return try getStashCount(at: path) > 0
    }
}

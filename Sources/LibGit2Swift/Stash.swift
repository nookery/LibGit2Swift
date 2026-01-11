import Foundation
import Clibgit2
import OSLog

/// LibGit2 暂存操作扩展
extension LibGit2 {
    /// 暂存当前变更
    /// - Parameters:
    ///   - message: 暂存信息（可选）
    ///   - path: 仓库路径
    /// - Returns: 暂存索引
    static func stash(message: String? = nil, at path: String) throws -> Int {
        os_log("🐚 LibGit2: Stashing changes")

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 检查是否有变更
        if !(try hasUncommittedChanges(at: path)) {
            os_log("🐚 LibGit2: No changes to stash")
            return -1
        }

        // 创建签名
        let (configName, configEmail) = try getUserConfig(at: path)
        var signature: UnsafeMutablePointer<git_signature>? = nil
        defer { if let sig = signature { git_signature_free(sig) } }
        git_signature_now(&signature, configName, configEmail)

        var commitOID = git_oid()

        let result: Int32
        if let message = message {
            result = git_stash_save(&commitOID, repo, signature, message, 0)
        } else {
            result = git_stash_save(&commitOID, repo, signature, "WIP", 0)
        }

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        // 获取 stash 索引
        let stashIndex = try getStashCount(at: path) - 1

        os_log("🐚 LibGit2: Changes stashed at index: %d", stashIndex)

        return stashIndex
    }

    /// 恢复暂存的变更
    /// - Parameters:
    ///   - index: 暂存索引（默认 0，即最近的 stash）
    ///   - path: 仓库路径
    static func stashPop(index: Int = 0, at path: String) throws {
        os_log("🐚 LibGit2: Popping stash at index: %d", index)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var stashOpts = git_stash_apply_options()
        git_stash_apply_init_options(&stashOpts, UInt32(GIT_STASH_APPLY_OPTIONS_VERSION))

        let result = git_stash_pop(repo, index, &stashOpts)

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        os_log("🐚 LibGit2: Stash popped successfully")
    }

    /// 应用暂存的变更（不从 stash 列表中删除）
    /// - Parameters:
    ///   - index: 暂存索引（默认 0，即最近的 stash）
    ///   - path: 仓库路径
    static func stashApply(index: Int = 0, at path: String) throws {
        os_log("🐚 LibGit2: Applying stash at index: %d", index)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var stashOpts = git_stash_apply_options()
        git_stash_apply_init_options(&stashOpts, UInt32(GIT_STASH_APPLY_OPTIONS_VERSION))
        
        stashOpts.checkout_options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        let result = git_stash_apply(repo, index, &stashOpts)

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        os_log("🐚 LibGit2: Stash applied successfully")
    }

    /// 获取暂存列表
    /// - Parameter path: 仓库路径
    /// - Returns: 暂存信息列表
    static func getStashList(at path: String) throws -> [(index: Int, message: String, commitHash: String)] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var referenceIterator: UnsafeMutablePointer<git_reference_iterator>? = nil
        defer {
            if let it = referenceIterator {
                git_reference_iterator_free(it)
            }
        }

        var stashes: [(index: Int, message: String, commitHash: String)] = []
        var index = 0

        if git_reference_iterator_new(&referenceIterator, repo) == 0, let iterator = referenceIterator {
            var reference: OpaquePointer? = nil
            while git_reference_next(&reference, iterator) == 0, let ref = reference {
                let name = git_reference_name(ref)

                if let namePtr = name, String(cString: namePtr).hasPrefix("refs/stash") {
                    defer { git_reference_free(ref) }

                    var commitOID = git_oid()
                    if git_reference_name_to_id(&commitOID, repo, String(cString: namePtr)) == 0 {
                        var commit: OpaquePointer? = nil
                        defer { if commit != nil { git_commit_free(commit) } }

                        if git_commit_lookup(&commit, repo, &commitOID) == 0, let commitPtr = commit {
                            let messagePtr = git_commit_message(commitPtr)
                            let message = messagePtr != nil ? String(cString: messagePtr!) : ""
                            let shortMessage = message.components(separatedBy: "\n").first ?? message
                            let commitHash = oidToString(commitOID)

                            stashes.append((index: index, message: shortMessage, commitHash: commitHash))
                            index += 1
                        }
                    }
                }
            }
        }

        return stashes
    }

    /// 删除暂存
    /// - Parameters:
    ///   - index: 暂存索引（默认 0，即最近的 stash）
    ///   - path: 仓库路径
    static func stashDrop(index: Int = 0, at path: String) throws {
        os_log("🐚 LibGit2: Dropping stash at index: %d", index)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let result = git_stash_drop(repo, index)

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        os_log("🐚 LibGit2: Stash dropped successfully")
    }

    /// 清空所有暂存
    /// - Parameter path: 仓库路径
    static func stashClear(at path: String) throws {
        os_log("🐚 LibGit2: Clearing all stashes")

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let count = try getStashCount(at: path)

        // 从后往前删除，避免索引问题
        for i in stride(from: count - 1, through: 0, by: -1) {
            git_stash_drop(repo, i)
        }

        os_log("🐚 LibGit2: All stashes cleared")
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

import Foundation
import Clibgit2
import OSLog

/// LibGit2 合并操作扩展
extension LibGit2 {
    /// 合并分支
    /// - Parameters:
    ///   - branchName: 要合并的分支名称
    ///   - path: 仓库路径
    public static func merge(branchName: String, at path: String) throws {
        os_log("🐚 LibGit2: Merging branch: %{public}@", branchName)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 查找要合并的分支
        let branchRef = "refs/heads/\(branchName)"
        var branchRefPtr: OpaquePointer? = nil
        defer { if branchRefPtr != nil { git_reference_free(branchRefPtr) } }

        let lookupResult = git_reference_lookup(&branchRefPtr, repo, branchRef)

        if lookupResult != 0 {
            throw LibGit2Error.checkoutFailed(branchName)
        }

        guard let branchRefValue = branchRefPtr else {
            throw LibGit2Error.invalidReference
        }

        // 获取分支的 annotated commit
        var branchOID = git_oid()
        git_reference_name_to_id(&branchOID, repo, branchRef)

        var annotatedCommit: OpaquePointer? = nil
        defer { if annotatedCommit != nil { git_annotated_commit_free(annotatedCommit) } }

        if git_annotated_commit_lookup(&annotatedCommit, repo, &branchOID) != 0 {
            throw LibGit2Error.mergeConflict
        }

        // 分析合并
        var analysis = git_merge_analysis_t.init(0)
        var preference = git_merge_preference_t.init(0)

        var headOID = git_oid()
        git_reference_name_to_id(&headOID, repo, "HEAD")

        var headAnnotatedCommit: OpaquePointer? = nil
        defer { if headAnnotatedCommit != nil { git_annotated_commit_free(headAnnotatedCommit) } }

        git_annotated_commit_lookup(&headAnnotatedCommit, repo, &headOID)

        git_merge_analysis(&analysis, &preference, repo, &annotatedCommit, 1)

        // 检查是否已经是最新
        if analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue != 0 {
            os_log("🐚 LibGit2: Already up to date")
            return
        }

        // 执行合并
        var mergeOpts = git_merge_options()
        git_merge_init_options(&mergeOpts, UInt32(GIT_MERGE_OPTIONS_VERSION))

        var checkoutOpts = git_checkout_options()
        git_checkout_init_options(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
        checkoutOpts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

        let mergeResult = git_merge(repo, &annotatedCommit, 1, &mergeOpts, &checkoutOpts)

        if mergeResult != 0 {
            throw LibGit2Error.mergeConflict
        }

        // 检查是否有冲突
        if try hasMergeConflicts(at: path) {
            os_log("⚠️ LibGit2: Merge conflicts detected")
            throw LibGit2Error.mergeConflict
        }

        // 创建合并提交
        try createMergeCommit(branchName: branchName, at: path)

        os_log("🐚 LibGit2: Merge completed successfully")
    }

    /// 快进合并
    /// - Parameters:
    ///   - branchName: 要合并的分支名称
    ///   - path: 仓库路径
    static func mergeFastForward(branchName: String, at path: String) throws {
        os_log("🐚 LibGit2: Fast-forward merging branch: %{public}@", branchName)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let branchRef = "refs/heads/\(branchName)"
        var branchOID = git_oid()

        guard git_reference_name_to_id(&branchOID, repo, branchRef) == 0 else {
            throw LibGit2Error.checkoutFailed(branchName)
        }

        // 分析是否可以快进
        var annotatedCommit: OpaquePointer? = nil
        defer { if annotatedCommit != nil { git_annotated_commit_free(annotatedCommit) } }

        git_annotated_commit_lookup(&annotatedCommit, repo, &branchOID)

        var analysis = git_merge_analysis_t.init(0)
        var preference = git_merge_preference_t.init(0)

        git_merge_analysis(&analysis, &preference, repo, &annotatedCommit, 1)

        if analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue == 0 {
            throw LibGit2Error.mergeConflict
        }

        // 执行快进
        var headRef: OpaquePointer? = nil
        defer { if headRef != nil { git_reference_free(headRef) } }

        if git_reference_lookup(&headRef, repo, "HEAD") == 0 {
            var updatedRef: OpaquePointer? = nil
            git_reference_set_target(&updatedRef, headRef!, &branchOID, "merge: fast-forward")
            git_reference_free(updatedRef)
        }

        // 更新工作目录
        var headCommit: OpaquePointer? = nil
        defer { if headCommit != nil { git_commit_free(headCommit) } }

        git_commit_lookup(&headCommit, repo, &branchOID)

        if let commit = headCommit {
            var tree: OpaquePointer? = nil
            defer { if tree != nil { git_tree_free(tree) } }

            git_commit_tree(&tree, commit)

            if let treePtr = tree {
                var checkoutOpts = git_checkout_options()
                git_checkout_init_options(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
                checkoutOpts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

                git_checkout_tree(repo, treePtr, &checkoutOpts)
            }
        }

        os_log("🐚 LibGit2: Fast-forward merge completed")
    }

    /// 获取合并冲突文件列表
    /// - Parameter path: 仓库路径
    /// - Returns: 冲突文件路径列表
    static func getMergeConflictFiles(at path: String) throws -> [String] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var index: OpaquePointer? = nil
        defer { if index != nil { git_index_free(index) } }

        guard git_repository_index(&index, repo) == 0 else {
            throw LibGit2Error.cannotGetIndex
        }

        var conflictFiles: [String] = []
        let count = git_index_entrycount(index!)

        for i in 0..<count {
            let entry = git_index_get_byindex(index!, i)

            if entry != nil && git_index_entry_is_conflict(entry!) == 1 {
                if let path = entry!.pointee.path {
                    conflictFiles.append(String(cString: path))
                }
            }
        }

        return conflictFiles
    }

    /// 检查是否有合并冲突
    /// - Parameter path: 仓库路径
    /// - Returns: 如果有冲突返回 true
    static func hasMergeConflicts(at path: String) throws -> Bool {
        let conflicts = try getMergeConflictFiles(at: path)
        return !conflicts.isEmpty
    }

    /// 检查是否正在合并
    /// - Parameter path: 仓库路径
    /// - Returns: 如果正在合并返回 true
    static func isMerging(at path: String) throws -> Bool {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 检查 MERGE_HEAD 是否存在
        var mergeHeadOID = git_oid()
        let result = git_reference_name_to_id(&mergeHeadOID, repo, "MERGE_HEAD")
        return result == 0
    }

    /// 中止合并
    /// - Parameter path: 仓库路径
    static func abortMerge(at path: String) throws {
        os_log("🐚 LibGit2: Aborting merge")

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 清理合并状态
        git_repository_state_cleanup(repo)

        // 重置到 HEAD
        var headOID = git_oid()
        if git_reference_name_to_id(&headOID, repo, "HEAD") == 0 {
            var headCommit: OpaquePointer? = nil
            defer { if headCommit != nil { git_commit_free(headCommit) } }

            if git_commit_lookup(&headCommit, repo, &headOID) == 0 {
                git_reset(repo, headCommit!, GIT_RESET_HARD, nil)
            }
        }

        os_log("🐚 LibGit2: Merge aborted")
    }

    /// 继续合并（解决冲突后创建合并提交）
    /// - Parameters:
    ///   - branchName: 分支名称
    ///   - path: 仓库路径
    static func continueMerge(branchName: String, at path: String) throws {
        os_log("🐚 LibGit2: Continuing merge")

        // 创建合并提交
        try createMergeCommit(branchName: branchName, at: path)

        // 清理合并状态
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        git_repository_state_cleanup(repo)

        os_log("🐚 LibGit2: Merge continued")
    }

    // MARK: - 私有辅助方法

    /// 创建合并提交
    private static func createMergeCommit(branchName: String, at path: String) throws {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 获取 MERGE_HEAD
        var mergeHeadOID = git_oid()
        guard git_reference_name_to_id(&mergeHeadOID, repo, "MERGE_HEAD") == 0 else {
            throw LibGit2Error.mergeConflict
        }

        var mergeHeadCommit: OpaquePointer? = nil
        defer { if mergeHeadCommit != nil { git_commit_free(mergeHeadCommit) } }

        guard git_commit_lookup(&mergeHeadCommit, repo, &mergeHeadOID) == 0 else {
            throw LibGit2Error.mergeConflict
        }

        // 获取 HEAD
        var headOID = git_oid()
        guard git_reference_name_to_id(&headOID, repo, "HEAD") == 0 else {
            throw LibGit2Error.cannotGetHEAD
        }

        var headCommit: OpaquePointer? = nil
        defer { if headCommit != nil { git_commit_free(headCommit) } }

        guard git_commit_lookup(&headCommit, repo, &headOID) == 0 else {
            throw LibGit2Error.cannotGetHEAD
        }

        // 写入 tree
        var index: OpaquePointer? = nil
        defer { if index != nil { git_index_free(index) } }

        guard git_repository_index(&index, repo) == 0 else {
            throw LibGit2Error.cannotGetIndex
        }

        var treeOID = git_oid()
        guard git_index_write_tree(&treeOID, index) == 0 else {
            throw LibGit2Error.cannotWriteTree
        }

        var tree: OpaquePointer? = nil
        defer { if tree != nil { git_tree_free(tree) } }

        guard git_tree_lookup(&tree, repo, &treeOID) == 0 else {
            throw LibGit2Error.cannotWriteTree
        }

        // 创建签名
        let (userName, userEmail) = try getUserConfig(at: path)
        var signature: UnsafeMutablePointer<git_signature>? = nil
        defer { if let sig = signature { git_signature_free(sig) } }
        git_signature_now(&signature, userName, userEmail)

        // 构建合并提交信息
        let message = "Merge branch '\(branchName)'"

        // 创建提交（两个父提交）
        var parents = [OpaquePointer?]()
        defer {
            for parent in parents {
                if parent != nil {
                    git_commit_free(parent!)
                }
            }
        }

        parents.append(headCommit)
        parents.append(mergeHeadCommit)

        var commitOID = git_oid()

        let result = git_commit_create(
            &commitOID,
            repo,
            "HEAD",
            signature,
            signature,
            nil,
            message,
            tree,
            2,
            &parents
        )

        if result != 0 {
            throw LibGit2Error.commitFailed
        }
    }
}

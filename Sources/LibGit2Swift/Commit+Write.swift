import Foundation
import Clibgit2
import OSLog

/// LibGit2 提交写入操作扩展
extension LibGit2 {
    /// 创建提交
    /// - Parameters:
    ///   - message: 提交信息
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    /// - Returns: 创建的提交哈希
    public static func createCommit(message: String, at path: String, verbose: Bool = true) throws -> String {
        if verbose { os_log("\(self.t)Creating commit with message: \(message)") }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 1. 获取 index
        var index: OpaquePointer? = nil
        defer { if index != nil { git_index_free(index) } }

        guard git_repository_index(&index, repo) == 0,
              let indexPtr = index else {
            throw LibGit2Error.cannotGetIndex
        }

        // 2. 检查是否有变更
        if git_index_entrycount(indexPtr) == 0 {
            // 检查是否有未提交的变更
            let hasChanges = try hasUncommittedChanges(at: path)
            if !hasChanges {
                throw LibGit2Error.nothingToCommit
            }
        }

        // 3. 写入 tree
        var treeOID = git_oid()
        let treeResult = git_index_write_tree(&treeOID, indexPtr)

        if treeResult != 0 {
            throw LibGit2Error.cannotWriteTree
        }

        var tree: OpaquePointer? = nil
        defer { if tree != nil { git_tree_free(tree) } }

        guard git_tree_lookup(&tree, repo, &treeOID) == 0 else {
            throw LibGit2Error.cannotWriteTree
        }

        // 4. 获取 HEAD commit 作为父提交
        var headCommit: OpaquePointer? = nil
        var parents = [OpaquePointer?]()
        defer {
            for parent in parents {
                if parent != nil {
                    git_commit_free(parent!)
                }
            }
        }
        
        var headOID = git_oid()
        if git_reference_name_to_id(&headOID, repo, "HEAD") == 0 {
            if git_commit_lookup(&headCommit, repo, &headOID) == 0, let commit = headCommit {
                parents.append(commit)
                headCommit = nil // set to nil for deferred free list to take over
            }
        }

        // 5. 创建签名
        let (userName, userEmail) = try getUserConfig(at: path)
        var signature: UnsafeMutablePointer<git_signature>? = nil
        defer { if let sig = signature { git_signature_free(sig) } }

        let signResult = git_signature_now(&signature, userName, userEmail)
        if signResult != 0 {
            // 如果配置失败，使用默认值
            if verbose { os_log("⚠️ LibGit2: Failed to create signature, using defaults") }
            git_signature_now(&signature, "GitOK User", "gitok@example.com")
        }

        // 6. 创建提交
        var commitOID = git_oid()
        let commitResult = parents.withUnsafeMutableBufferPointer { buffer in
            return git_commit_create(
                &commitOID,
                repo,
                "HEAD",
                signature,
                signature,
                nil,
                message,
                tree,
                buffer.count,
                buffer.baseAddress
            )
        }

        if commitResult != 0 {
            throw LibGit2Error.commitFailed
        }

        let commitHash = oidToString(commitOID)
        if verbose { os_log("\(self.t)Commit created successfully: \(commitHash)") }

        return commitHash
    }

    /// 添加文件并提交
    /// - Parameters:
    ///   - files: 要添加的文件路径列表（空数组表示添加所有变更）
    ///   - message: 提交信息
    ///   - path: 仓库路径
    /// - Returns: 创建的提交哈希
    static func addAndCommit(files: [String], message: String, at path: String, verbose: Bool = true) throws -> String {
        if verbose { os_log("\(self.t)Adding and committing files: \(files)") }
        try addFiles(files, at: path)
        return try createCommit(message: message, at: path, verbose: verbose)
    }

    /// 修改最后一次提交（amend）
    /// - Parameters:
    ///   - message: 新的提交信息（nil 表示不修改）
    ///   - path: 仓库路径
    /// - Returns: 新的提交哈希
        static func amendCommit(message: String? = nil, at path: String, verbose: Bool = true) throws -> String {
        if verbose { os_log("\(self.t)Amending commit with message: \(message ?? "nil")") }
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 获取 HEAD commit
        var headOID = git_oid()
        guard git_reference_name_to_id(&headOID, repo, "HEAD") == 0 else {
            throw LibGit2Error.cannotGetHEAD
        }

        var headCommit: OpaquePointer? = nil
        defer { if headCommit != nil { git_commit_free(headCommit) } }

        guard git_commit_lookup(&headCommit, repo, &headOID) == 0,
              let commit = headCommit else {
            throw LibGit2Error.cannotGetHEAD
        }

        // 获取当前 index tree
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

        // 获取父提交的父提交（祖父母）
        let parentCount = git_commit_parentcount(commit)
        var parents = [OpaquePointer?]()
        defer {
            for parent in parents {
                if parent != nil {
                    git_commit_free(parent!)
                }
            }
        }

        for i in 0..<parentCount {
            var parent: OpaquePointer? = nil
            if git_commit_parent(&parent, commit, i) == 0 {
                parents.append(parent)
            }
        }

        // 创建签名
        let (userName, userEmail) = try getUserConfig(at: path)
        var signature: UnsafeMutablePointer<git_signature>? = nil
        defer { if let sig = signature { git_signature_free(sig) } }
        git_signature_now(&signature, userName, userEmail)

        // 创建新提交
        var newCommitOID = git_oid()
        let messageToUpdate = message ?? String(cString: git_commit_message(commit))

        let result = parents.withUnsafeMutableBufferPointer { buffer in
            return git_commit_create(
                &newCommitOID,
                repo,
                "HEAD",
                signature,
                signature,
                nil,
                messageToUpdate,
                tree,
                buffer.count,
                buffer.baseAddress
            )
        }

        if result != 0 {
            throw LibGit2Error.commitFailed
        }

        return oidToString(newCommitOID)
    }
}

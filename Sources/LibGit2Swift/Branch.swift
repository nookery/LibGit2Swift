import Foundation
import Clibgit2
import OSLog


/// LibGit2 分支操作扩展
extension LibGit2 {
    /// 获取分支列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - includeRemote: 是否包含远程分支
    /// - Returns: 分支列表
    /// 获取分支列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - includeRemote: 是否包含远程分支
    /// - Returns: 分支列表
    public static func getBranchList(at path: String, includeRemote: Bool = false) throws -> [GitBranch] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var branches: [GitBranch] = []
        var branchIterator: OpaquePointer? = nil
        defer { git_branch_iterator_free(branchIterator) }

        let branchType = includeRemote ? GIT_BRANCH_ALL : GIT_BRANCH_LOCAL
        let result = git_branch_iterator_new(&branchIterator, repo, branchType)

        guard result == 0, let iterator = branchIterator else {
            return branches
        }

        var branchRef: OpaquePointer? = nil
        var branchTypeValue = git_branch_t.init(0)

        // 遍历所有分支
        while git_branch_next(&branchRef, &branchTypeValue, iterator) == 0 {
            guard let ref = branchRef else { continue }

            defer { git_reference_free(ref) }

            // 获取分支名
            var namePtr: UnsafePointer<Int8>? = nil
            if git_branch_name(&namePtr, ref) == 0, let name = namePtr {
                let branchName = String(cString: name)

                // 检查是否为当前分支
                let isHead = git_branch_is_head(ref) == 1

                // 获取分支的最新提交
                var commitOid = git_oid()
                var latestCommitHash = ""
                var latestCommitMessage = ""

                if let target = git_reference_target(ref) {
                    var commit: OpaquePointer? = nil
                    defer { if commit != nil { git_commit_free(commit) } }

                    if git_commit_lookup(&commit, repo, target) == 0, let commitPtr = commit {
                        let messagePtr = git_commit_message(commitPtr)
                        if let msg = messagePtr {
                            latestCommitMessage = String(cString: msg).components(separatedBy: "\n").first ?? ""
                        }
                    }
                }

                // 获取上游分支
                var upstream: String? = nil
                var upstreamRef: OpaquePointer? = nil
                defer { if upstreamRef != nil { git_reference_free(upstreamRef) } }

                if git_branch_upstream(&upstreamRef, ref) == 0, let us = upstreamRef {
                    var upstreamNamePtr: UnsafePointer<Int8>? = nil
                    if git_branch_name(&upstreamNamePtr, us) == 0, let usName = upstreamNamePtr {
                        // 添加远程前缀（如果需要）
                        if branchTypeValue == GIT_BRANCH_LOCAL {
                            upstream = String(cString: usName)
                        } else {
                            upstream = String(cString: usName)
                        }
                    }
                }

                // 添加分支类型前缀（远程分支）
                let displayName = branchTypeValue == GIT_BRANCH_REMOTE ? String(cString: name) : String(cString: name)

                branches.append(GitBranch(
                    id: displayName,
                    name: displayName,
                    isCurrent: isHead,
                    upstream: upstream,
                    latestCommitHash: latestCommitHash,
                    latestCommitMessage: latestCommitMessage
                ))
            }
        }

        return branches
    }

    /// 获取本地分支列表
    public static func getLocalBranches(at path: String) throws -> [GitBranch] {
        return try getBranchList(at: path, includeRemote: false)
    }

    /// 获取远程分支列表
    public static func getRemoteBranches(at path: String) throws -> [GitBranch] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var branches: [GitBranch] = []
        var branchIterator: OpaquePointer? = nil
        defer { git_branch_iterator_free(branchIterator) }

        let result = git_branch_iterator_new(&branchIterator, repo, GIT_BRANCH_REMOTE)

        guard result == 0, let iterator = branchIterator else {
            return branches
        }

        var branchRef: OpaquePointer? = nil
        var branchTypeValue = git_branch_t.init(0)

        while git_branch_next(&branchRef, &branchTypeValue, iterator) == 0 {
            guard let ref = branchRef else { continue }

            defer { git_reference_free(ref) }

            var namePtr: UnsafePointer<Int8>? = nil
            if git_branch_name(&namePtr, ref) == 0, let name = namePtr {
                let branchName = String(cString: name)

                // 移除 "origin/" 前缀
                let shortName = branchName.replacingOccurrences(of: "^[^/]+/", with: "", options: .regularExpression)

                var commitOid = git_oid()
                var latestCommitHash = ""
                var latestCommitMessage = ""

                if let target = git_reference_target(ref) {
                    commitOid = target.pointee
                    latestCommitHash = oidToString(commitOid)

                    var commit: OpaquePointer? = nil
                    defer { if commit != nil { git_commit_free(commit) } }

                    if git_commit_lookup(&commit, repo, &commitOid) == 0, let commitPtr = commit {
                        let messagePtr = git_commit_message(commitPtr)
                        if let msg = messagePtr {
                            latestCommitMessage = String(cString: msg).components(separatedBy: "\n").first ?? ""
                        }
                    }
                }

                branches.append(GitBranch(
                    id: branchName,
                    name: shortName,
                    isCurrent: false,
                    upstream: nil,
                    latestCommitHash: latestCommitHash,
                    latestCommitMessage: latestCommitMessage
                ))
            }
        }

        return branches
    }

    /// 获取当前分支信息
    public static func getCurrentBranchInfo(at path: String) throws -> GitBranch? {
        let branches = try getBranchList(at: path, includeRemote: false)
        return branches.first { $0.isCurrent }
    }

    /// 创建新分支
    /// - Parameters:
    ///   - name: 分支名称
    ///   - path: 仓库路径
    ///   - checkout: 是否立即切换到新分支
    /// - Returns: 创建的分支名称
    public static func createBranch(named name: String, at path: String, checkout: Bool = false) throws -> String {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 获取 HEAD commit
        var headCommit: OpaquePointer? = nil
        defer { if headCommit != nil { git_commit_free(headCommit) } }

        var headOid = git_oid()
        let result = git_reference_name_to_id(&headOid, repo, "HEAD")

        if result != 0 {
            throw LibGit2Error.cannotGetHEAD
        }

        git_commit_lookup(&headCommit, repo, &headOid)

        guard let commit = headCommit else {
            throw LibGit2Error.cannotGetHEAD
        }

        // 创建分支
        var branch: OpaquePointer? = nil
        defer { if branch != nil { git_reference_free(branch) } }

        let createResult = git_branch_create(&branch, repo, name, commit, 0)

        if createResult != 0 {
            throw LibGit2Error.checkoutFailed(name)
        }

        // 如果需要，切换到新分支
        if checkout {
            try LibGit2.checkout(branch: name, at: path)
        }

        return name
    }

    /// 删除分支
    /// - Parameters:
    ///   - name: 分支名称
    ///   - path: 仓库路径
    ///   - force: 是否强制删除
    public static func deleteBranch(named name: String, at path: String, force: Bool = false) throws {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var branchRef: OpaquePointer? = nil
        defer { if branchRef != nil { git_reference_free(branchRef) } }

        let result = git_branch_lookup(&branchRef, repo, name, GIT_BRANCH_LOCAL)

        if result != 0 {
            throw LibGit2Error.invalidReference
        }

        let deleteResult = git_branch_delete(branchRef!)

        if deleteResult != 0 {
            throw LibGit2Error.checkoutFailed(name)
        }
    }

    /// 重命名分支
    /// - Parameters:
    ///   - name: 原分支名称
    ///   - newName: 新分支名称
    ///   - path: 仓库路径
    ///   - force: 是否强制重命名
    public static func renameBranch(named name: String, to newName: String, at path: String, force: Bool = false) throws {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var branchRef: OpaquePointer? = nil
        defer { if branchRef != nil { git_reference_free(branchRef) } }

        let result = git_branch_lookup(&branchRef, repo, name, GIT_BRANCH_LOCAL)

        if result != 0 {
            throw LibGit2Error.invalidReference
        }

        var newRef: OpaquePointer? = nil
        defer { if newRef != nil { git_reference_free(newRef) } }

        let renameResult = git_branch_move(&newRef, branchRef!, newName, force ? 1 : 0)

        if renameResult != 0 {
            throw LibGit2Error.checkoutFailed(newName)
        }
    }
}

import Foundation
import Clibgit2
import OSLog


/// LibGit2 提交历史操作扩展
extension LibGit2 {
    /// 获取提交列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - limit: 最大返回数量
    ///   - skip: 跳过的提交数量
    /// - Returns: 提交列表
    /// 获取提交列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - limit: 最大返回数量
    ///   - skip: 跳过的提交数量
    /// - Returns: 提交列表
    public static func getCommitList(at path: String, limit: Int = Int.max, skip: Int = 0) throws -> [GitCommit] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var revwalk: OpaquePointer? = nil
        defer { if revwalk != nil { git_revwalk_free(revwalk) } }

        let result = git_revwalk_new(&revwalk, repo)

        guard result == 0, let walker = revwalk else {
            throw LibGit2Error.cannotCreateRevwalk
        }

        // 按时间倒序排序
        git_revwalk_sorting(walker, GIT_SORT_TIME.rawValue)

        // 从 HEAD 开始遍历
        git_revwalk_push_head(walker)

        var commits: [GitCommit] = []
        var oid = git_oid()
        var count = 0
        var skipped = 0

        // 跳过指定数量的提交
        while skipped < skip && git_revwalk_next(&oid, walker) == 0 {
            skipped += 1
        }

        // 遍历提交
        while git_revwalk_next(&oid, walker) == 0 && count < limit {
            var commit: OpaquePointer? = nil
            defer { if commit != nil { git_commit_free(commit) } }

            let lookupResult = git_commit_lookup(&commit, repo, &oid)

            if lookupResult == 0, let commitPtr = commit {
                if let gitCommit = parseCommit(commitPtr, repo: repo) {
                    commits.append(gitCommit)
                    count += 1
                }
            }
        }

        return commits
    }

    /// 分页获取提交列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - page: 页码（从 0 开始）
    ///   - size: 每页大小
    /// - Returns: 提交列表
    public static func getCommitListWithPagination(at path: String, page: Int, size: Int) throws -> [GitCommit] {
        return try getCommitList(at: path, limit: size, skip: page * size)
    }

    /// 获取指定分支的提交列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - branch: 分支名称
    ///   - limit: 最大返回数量
    /// - Returns: 提交列表
    public static func getCommitList(on branch: String, at path: String, limit: Int = Int.max) throws -> [GitCommit] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var revwalk: OpaquePointer? = nil
        defer { if revwalk != nil { git_revwalk_free(revwalk) } }

        let result = git_revwalk_new(&revwalk, repo)

        guard result == 0, let walker = revwalk else {
            throw LibGit2Error.cannotCreateRevwalk
        }

        git_revwalk_sorting(walker, GIT_SORT_TIME.rawValue)

        // 推送分支引用
        let branchRef = "refs/heads/\(branch)"
        var oid = git_oid()

        if git_reference_name_to_id(&oid, repo, branchRef) != 0 {
            throw LibGit2Error.invalidReference
        }

        git_revwalk_push(walker, &oid)

        var commits: [GitCommit] = []
        var commitOid = git_oid()
        var count = 0

        while git_revwalk_next(&commitOid, walker) == 0 && count < limit {
            var commit: OpaquePointer? = nil
            defer { if commit != nil { git_commit_free(commit) } }

            if git_commit_lookup(&commit, repo, &commitOid) == 0, let commitPtr = commit {
                if let gitCommit = parseCommit(commitPtr, repo: repo) {
                    commits.append(gitCommit)
                    count += 1
                }
            }
        }

        return commits
    }

    /// 获取未推送的提交列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - remote: 远程仓库名称
    ///   - branch: 分支名称
    /// - Returns: 未推送的提交列表
    static func getUnpushedCommitList(at path: String, remote: String, branch: String) throws -> [GitCommit] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var revwalk: OpaquePointer? = nil
        defer { if revwalk != nil { git_revwalk_free(revwalk) } }

        let result = git_revwalk_new(&revwalk, repo)

        guard result == 0, let walker = revwalk else {
            throw LibGit2Error.cannotCreateRevwalk
        }

        git_revwalk_sorting(walker, GIT_SORT_TIME.rawValue)

        // 获取本地分支
        let localBranchRef = "refs/heads/\(branch)"
        var localOid = git_oid()

        if git_reference_name_to_id(&localOid, repo, localBranchRef) != 0 {
            throw LibGit2Error.invalidReference
        }

        // 获取远程分支
        let remoteBranchRef = "refs/remotes/\(remote)/\(branch)"
        var remoteOid = git_oid()

        var hasRemote = false
        if git_reference_name_to_id(&remoteOid, repo, remoteBranchRef) == 0 {
            hasRemote = true
        }

        // 推送本地分支，隐藏远程分支之前的提交
        git_revwalk_push(walker, &localOid)

        if hasRemote {
            git_revwalk_hide(walker, &remoteOid)
        }

        var commits: [GitCommit] = []
        var commitOid = git_oid()

        while git_revwalk_next(&commitOid, walker) == 0 {
            var commit: OpaquePointer? = nil
            defer { if commit != nil { git_commit_free(commit) } }

            if git_commit_lookup(&commit, repo, &commitOid) == 0, let commitPtr = commit {
                if let gitCommit = parseCommit(commitPtr, repo: repo) {
                    commits.append(gitCommit)
                }
            }
        }

        return commits
    }

    /// 获取指定提交的详细信息
    /// - Parameters:
    ///   - commitHash: 提交哈希
    ///   - path: 仓库路径
    /// - Returns: 提交详细信息
    static func getCommitDetail(commitHash: String, at path: String) throws -> GitCommit? {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var oid = git_oid()
        let result = git_oid_fromstr(&oid, commitHash)

        if result != 0 {
            throw LibGit2Error.invalidValue
        }

        var commit: OpaquePointer? = nil
        defer { if commit != nil { git_commit_free(commit) } }

        if git_commit_lookup(&commit, repo, &oid) == 0, let commitPtr = commit {
            return parseCommit(commitPtr, repo: repo)
        }

        return nil
    }

    // MARK: - 私有辅助方法

    /// 解析 commit 指针为 GitCommit 结构体
    private static func parseCommit(_ commit: OpaquePointer, repo: OpaquePointer) -> GitCommit? {
        // 获取提交 ID
        let oid = git_commit_id(commit)
        let hash = oidToString(oid!.pointee)

        // 获取作者信息
        let authorPtr = git_commit_author(commit)
        guard let author = authorPtr else { return nil }

        let authorName = String(cString: author.pointee.name)
        let authorEmail = String(cString: author.pointee.email)

        // 获取提交时间
        let time = author.pointee.when.time
        let date = Date(timeIntervalSince1970: TimeInterval(time))

        // 获取提交信息
        let messagePtr = git_commit_message(commit)
        let message = messagePtr != nil ? String(cString: messagePtr!) : ""
        let body = message
        let shortMessage = message.components(separatedBy: "\n").first ?? message

        // 获取引用
        var refs: [String] = []

        // 获取该提交指向的所有引用
        var referenceIterator: UnsafeMutablePointer<git_reference_iterator>? = nil
        defer {
            if let it = referenceIterator {
                git_reference_iterator_free(it)
            }
        }

        if git_reference_iterator_new(&referenceIterator, repo) == 0, let iterator = referenceIterator {
            var reference: OpaquePointer? = nil
            while git_reference_next(&reference, iterator) == 0, let ref = reference {
                defer { git_reference_free(ref) }

                // 检查是否是直接引用（指向 commit）
                if git_reference_type(ref) == GIT_REFERENCE_DIRECT {
                    let targetOid = git_reference_target(ref)!
                    if git_oid_equal(oid, targetOid) == 1 {
                        let name = git_reference_name(ref)
                        if let namePtr = name {
                            let refName = String(cString: namePtr)
                            // 只添加分支和标签引用
                            if refName.hasPrefix("refs/heads/") || refName.hasPrefix("refs/tags/") {
                                refs.append(refName)
                            }
                        }
                    }
                }
            }
        }

        // 获取标签
        var tags: [String] = []
        for ref in refs {
            if ref.hasPrefix("refs/tags/") {
                let tagName = ref.replacingOccurrences(of: "refs/tags/", with: "")
                tags.append(tagName)
            }
        }

        return GitCommit(
            id: hash,
            hash: hash,
            author: authorName,
            email: authorEmail,
            date: date,
            message: shortMessage,
            body: body,
            refs: refs,
            tags: tags
        )
    }

    /// 获取提交的父提交数量
    private static func getParentCount(_ commit: OpaquePointer) -> Int {
        return Int(git_commit_parentcount(commit))
    }
}

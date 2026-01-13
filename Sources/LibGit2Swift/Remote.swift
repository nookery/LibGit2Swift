import Foundation
import Clibgit2
import OSLog


/// LibGit2 远程仓库操作扩展
extension LibGit2 {
    /// 获取未推送的提交（本地领先远程的提交）
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志
    /// - Returns: 未推送的提交列表
    public static func getUnPushedCommits(at path: String, verbose: Bool) throws -> [GitCommit] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 获取当前分支的 HEAD
        var headOID = git_oid()
        let headResult = git_reference_name_to_id(&headOID, repo, "HEAD")

        guard headResult == 0 else {
            // 无法获取 HEAD，返回空数组
            if verbose { os_log("\(Self.t)getUnPushedCommits: Cannot get HEAD") }
            return []
        }

        // 获取当前分支引用
        var headRef: OpaquePointer? = nil
        let lookupResult = git_reference_lookup(&headRef, repo, "HEAD")

        guard lookupResult == 0, let ref = headRef else {
            if verbose { os_log("\(Self.t)getUnPushedCommits: Cannot lookup HEAD reference") }
            return []
        }
        defer { git_reference_free(headRef) }

        // 解析 HEAD 到实际分支引用
        var targetRef: OpaquePointer? = nil
        let resolveResult = git_reference_resolve(&targetRef, ref)

        guard resolveResult == 0, let branchRef = targetRef else {
            if verbose { os_log("\(Self.t)getUnPushedCommits: Cannot resolve HEAD reference") }
            return []
        }
        defer { git_reference_free(targetRef) }

        // 获取上游分支
        var upstreamRef: OpaquePointer? = nil
        let branchResult = git_branch_upstream(&upstreamRef, branchRef)

        guard branchResult == 0, let upstream = upstreamRef else {
            // 没有上游分支，返回空数组
            if verbose { os_log("\(Self.t)getUnPushedCommits: No upstream branch configured") }
            return []
        }
        defer { git_reference_free(upstreamRef) }

        // 从上游分支引用获取分支名称
        // git_branch_upstream 返回的是 merge target，我们需要构建实际的远程跟踪分支引用
        let upstreamName = git_reference_shorthand(upstream)
        guard let namePtr = upstreamName else {
            if verbose { os_log("\(Self.t)getUnPushedCommits: Cannot get upstream branch name") }
            return []
        }
        let upstreamBranchName = String(cString: namePtr)

        if verbose {
            os_log("\(Self.t)getUnPushedCommits: Configured upstream: \(upstreamBranchName)")
        }

        // 构建远程跟踪分支的全名（refs/remotes/origin/main）
        // upstreamBranchName 格式为 "origin/main"，我们需要转换为 "refs/remotes/origin/main"
        let remoteTrackingBranchName = "refs/remotes/\(upstreamBranchName)"

        if verbose {
            os_log("\(Self.t)getUnPushedCommits: Looking for remote tracking branch: \(remoteTrackingBranchName)")
        }

        // 获取远程跟踪分支的 HEAD OID
        var upstreamOID = git_oid()
        let upstreamResult = git_reference_name_to_id(
            &upstreamOID,
            repo,
            remoteTrackingBranchName
        )

        guard upstreamResult == 0 else {
            // 无法获取上游 HEAD，返回空数组
            if verbose {
                os_log("\(Self.t)getUnPushedCommits: Cannot get upstream HEAD OID for \(remoteTrackingBranchName)")
            }
            return []
        }

        if verbose {
            let upstreamOIDStr = oidToString(upstreamOID)
            let headOIDStr = oidToString(headOID)
            os_log("\(Self.t)getUnPushedCommits: HEAD OID: \(headOIDStr)")
            os_log("\(Self.t)getUnPushedCommits: Remote tracking OID: \(upstreamOIDStr)")
        }

        // 比较本地和远程，获取领先/落后数量
        var ahead: Int = 0
        var behind: Int = 0
        let graphResult = git_graph_ahead_behind(&ahead, &behind, repo, &headOID, &upstreamOID)

        guard graphResult == 0 else {
            if verbose { os_log("\(Self.t)getUnPushedCommits: Cannot compare graphs") }
            return []
        }

        if verbose {
            os_log("\(Self.t)getUnPushedCommits: ahead=\(ahead), behind=\(behind)")
        }

        // 如果没有领先的提交，返回空数组
        guard ahead > 0 else {
            return []
        }

        // 获取未推送的提交列表
        var revwalk: OpaquePointer? = nil
        defer { if revwalk != nil { git_revwalk_free(revwalk) } }

        let walkResult = git_revwalk_new(&revwalk, repo)
        guard walkResult == 0, let walker = revwalk else {
            throw LibGit2Error.cannotCreateRevwalk
        }

        // 按拓扑顺序排序
        git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL.rawValue)

        // 推送本地 HEAD
        git_revwalk_push(walker, &headOID)

        // 隐藏上游提交及其之前的提交
        git_revwalk_hide(walker, &upstreamOID)

        var commits: [GitCommit] = []
        var oid = git_oid()
        var count = 0

        // 遍历提交
        while git_revwalk_next(&oid, walker) == 0 && count < ahead {
            var commit: OpaquePointer? = nil
            defer { if commit != nil { git_commit_free(commit) } }

            let lookupResult = git_commit_lookup(&commit, repo, &oid)

            if lookupResult == 0, let commitPtr = commit {
                if let gitCommit = parseCommitFromPointer(commitPtr, repo: repo) {
                    commits.append(gitCommit)
                    count += 1
                }
            }
        }

        return commits
    }

    /// 解析 commit 指针为 GitCommit 结构体（内部方法）
    private static func parseCommitFromPointer(_ commit: OpaquePointer, repo: OpaquePointer) -> GitCommit? {
        // 获取提交 ID
        let oid = git_commit_id(commit)
        guard let oidPtr = oid else { return nil }
        let hash = oidToString(oidPtr.pointee)

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
        let bodyPtr = git_commit_body(commit)
        let body = bodyPtr != nil ? String(cString: bodyPtr!) : ""

        // 获取引用和标签（简化版本，只返回空数组）
        let refs: [String] = []
        let tags: [String] = []

        return GitCommit(
            id: hash,
            hash: hash,
            author: authorName,
            email: authorEmail,
            date: date,
            message: message,
            body: body,
            refs: refs,
            tags: tags
        )
    }

    /// 获取未拉取的提交数量（远程领先本地的提交数量）
    /// - Parameter path: 仓库路径
    /// - Returns: 未拉取的提交数量
    public static func getUnPulledCount(at path: String) throws -> Int {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 获取当前分支的 HEAD
        var headOID = git_oid()
        let headResult = git_reference_name_to_id(&headOID, repo, "HEAD")

        guard headResult == 0 else {
            return 0
        }

        // 获取当前分支引用
        var headRef: OpaquePointer? = nil
        let lookupResult = git_reference_lookup(&headRef, repo, "HEAD")

        guard lookupResult == 0, let ref = headRef else {
            return 0
        }
        defer { git_reference_free(headRef) }

        // 解析 HEAD 到实际分支引用
        var targetRef: OpaquePointer? = nil
        let resolveResult = git_reference_resolve(&targetRef, ref)

        guard resolveResult == 0, let branchRef = targetRef else {
            return 0
        }
        defer { git_reference_free(targetRef) }

        // 获取上游分支
        var upstreamRef: OpaquePointer? = nil
        let branchResult = git_branch_upstream(&upstreamRef, branchRef)

        guard branchResult == 0, let upstream = upstreamRef else {
            // 没有上游分支
            return 0
        }
        defer { git_reference_free(upstreamRef) }

        // 从上游分支引用获取分支名称并构建远程跟踪分支的全名
        let upstreamName = git_reference_shorthand(upstream)
        guard let namePtr = upstreamName else {
            return 0
        }
        let upstreamBranchName = String(cString: namePtr)
        let remoteTrackingBranchName = "refs/remotes/\(upstreamBranchName)"

        // 获取远程跟踪分支的 HEAD OID
        var upstreamOID = git_oid()
        let upstreamResult = git_reference_name_to_id(
            &upstreamOID,
            repo,
            remoteTrackingBranchName
        )

        guard upstreamResult == 0 else {
            return 0
        }

        // 比较本地和远程，获取领先/落后数量
        var ahead: Int = 0
        var behind: Int = 0
        let graphResult = git_graph_ahead_behind(&ahead, &behind, repo, &headOID, &upstreamOID)

        guard graphResult == 0 else {
            return 0
        }

        return behind
    }

    /// 获取远程仓库列表
    /// - Parameter path: 仓库路径
    /// - Returns: 远程仓库列表
    public static func getRemoteList(at path: String) throws -> [GitRemote] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remoteNames = git_strarray()
        defer { git_strarray_free(&remoteNames) }

        let result = git_remote_list(&remoteNames, repo)

        if result != 0 {
            return []
        }

        var remotes: [GitRemote] = []
        let array = remoteNames

        for i in 0..<array.count {
            guard let namePtr = array.strings[i] else { continue }

            let name = String(cString: namePtr)

            var remote: OpaquePointer? = nil
            defer { if remote != nil { git_remote_free(remote) } }

            if git_remote_lookup(&remote, repo, name) == 0, let remotePtr = remote {
                let url = git_remote_url(remotePtr)
                let fetchURL = url != nil ? String(cString: url!) : nil

                // 如果没有单独的push URL，使用fetch URL
                var pushURL: String? = nil
                if let pushURLPtr = git_remote_pushurl(remotePtr) {
                    pushURL = String(cString: pushURLPtr)
                } else {
                    pushURL = fetchURL
                }

                let isDefault = name == "origin"

                remotes.append(GitRemote(
                    id: name,
                    name: name,
                    url: fetchURL ?? "",
                    fetchURL: fetchURL,
                    pushURL: pushURL,
                    isDefault: isDefault
                ))
            }
        }

        return remotes
    }

    /// 添加远程仓库
    /// - Parameters:
    ///   - name: 远程仓库名称
    ///   - url: 远程仓库 URL
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func addRemote(name: String, url: String, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Adding remote: %{public}@ -> %{public}@", name, url) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remote: OpaquePointer? = nil
        defer { if remote != nil { git_remote_free(remote) } }

        let result = git_remote_create(&remote, repo, name, url)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        if verbose { os_log("🐚 LibGit2: Remote added: %{public}@", name) }
    }

    /// 删除远程仓库
    /// - Parameters:
    ///   - name: 远程仓库名称
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func removeRemote(name: String, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Removing remote: %{public}@", name) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let result = git_remote_delete(repo, name)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        if verbose { os_log("🐚 LibGit2: Remote removed: %{public}@", name) }
    }

    /// 设置远程仓库 URL
    /// - Parameters:
    ///   - name: 远程仓库名称
    ///   - url: 新的 URL
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func setRemoteURL(name: String, url: String, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Setting remote URL: %{public}@ -> %{public}@", name, url) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remote: OpaquePointer? = nil
        defer { if remote != nil { git_remote_free(remote) } }

        let result = git_remote_lookup(&remote, repo, name)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        guard remote != nil else {
            throw LibGit2Error.remoteNotFound(name)
        }

        let setResult = git_remote_set_url(repo, name, url)

        if setResult != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        if verbose { os_log("🐚 LibGit2: Remote URL updated: %{public}@", name) }
    }

    /// 获取远程仓库的 URL
    /// - Parameters:
    ///   - name: 远程仓库名称
    ///   - path: 仓库路径
    /// - Returns: 远程仓库 URL
    public static func getRemoteURL(name: String, at path: String) throws -> String {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remote: OpaquePointer? = nil
        defer { if remote != nil { git_remote_free(remote) } }

        let result = git_remote_lookup(&remote, repo, name)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        guard let remotePtr = remote,
              let url = git_remote_url(remotePtr) else {
            throw LibGit2Error.remoteNotFound(name)
        }

        return String(cString: url)
    }

    /// 获取默认远程仓库的 URL（通常是 origin）
    /// - Parameter path: 仓库路径
    /// - Returns: 远程仓库 URL（如果存在）
    static func getFirstRemoteURL(at path: String) throws -> String? {
        let remotes = try getRemoteList(at: path)

        // 优先返回 origin
        if let origin = remotes.first(where: { $0.name == "origin" }) {
            return origin.url.isEmpty ? nil : origin.url
        }

        // 否则返回第一个远程仓库
        return remotes.first?.url
    }

    /// 重命名远程仓库
    /// - Parameters:
    ///   - oldName: 旧名称
    ///   - newName: 新名称
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func renameRemote(oldName: String, to newName: String, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Renaming remote: %{public}@ -> %{public}@", oldName, newName) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var problems = git_strarray()
        defer { git_strarray_free(&problems) }

        let result = git_remote_rename(&problems, repo, oldName, newName)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(oldName)
        }

        if verbose { os_log("🐚 LibGit2: Remote renamed") }
    }
}

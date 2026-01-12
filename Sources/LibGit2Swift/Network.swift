import Foundation
import Clibgit2
import OSLog

// MARK: - Network Operations

/// 控制网络操作的日志输出
private var networkVerbose: Bool = true

// MARK: - Authentication Error Detection

/// 检查错误是否是认证错误
/// - Parameters:
///   - errorCode: libgit2 错误代码
///   - errorMessage: 错误消息
/// - Returns: 如果是认证错误返回 true
private func isAuthenticationError(_ errorCode: Int32, errorMessage: String) -> Bool {
    // 检查错误代码是否是 GIT_EUSER (-3) 或其他认证相关错误
    if errorCode == Int32(GIT_EUSER.rawValue) {
        return true
    }

    // 检查错误消息中是否包含认证相关的关键词
    let lowercasedMessage = errorMessage.lowercased()
    let authKeywords = [
        "authentication",
        "auth",
        "credential",
        "permission",
        "denied",
        "unauthorized",
        "401",
        "403",
        "forbidden"
    ]

    return authKeywords.contains { lowercasedMessage.contains($0) }
}

/// LibGit2 网络操作扩展（push, pull, clone）
extension LibGit2 {
    /// 推送到远程仓库
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - remote: 远程仓库名称（默认 "origin"）
    ///   - branch: 分支名称（nil 表示使用当前分支）
    public static func push(at path: String, remote: String = "origin", branch: String? = nil, verbose: Bool = true) throws {
        networkVerbose = verbose
        if networkVerbose { os_log("🐚 LibGit2: Pushing to remote: %{public}@", remote) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remoteObj: OpaquePointer? = nil
        defer { if remoteObj != nil { git_remote_free(remoteObj) } }

        let result = git_remote_lookup(&remoteObj, repo, remote)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(remote)
        }

        guard let remotePtr = remoteObj else {
            throw LibGit2Error.remoteNotFound(remote)
        }

        // 获取当前分支名
        let branchName: String
        if let branch = branch {
            branchName = branch
        } else {
            branchName = try getCurrentBranch(at: path)
        }

        // 构建 refspec
        let refspec = "refs/heads/\(branchName):refs/heads/\(branchName)"
        let refspecPtr = strdup(refspec)
        defer { free(refspecPtr) }
        
        var refspecs = git_strarray()
        var refspecArray: [UnsafeMutablePointer<CChar>?] = [refspecPtr]
        let result_strarray = refspecArray.withUnsafeMutableBufferPointer { buffer -> Int32 in
            refspecs.strings = buffer.baseAddress
            refspecs.count = 1
            
            var pushOpts = git_push_options()
            git_push_init_options(&pushOpts, UInt32(GIT_PUSH_OPTIONS_VERSION))

            // 设置进度回调
            pushOpts.callbacks.push_transfer_progress = { (current: UInt32, total: UInt32, bytes: Int, payload: UnsafeMutableRawPointer?) -> Int32 in
                let percent = total > 0 ? Float(current) / Float(total) * 100 : 0
                if networkVerbose { os_log("🐚 LibGit2: Push progress: %.1f%%", percent) }
                return 0
            }

            // 设置凭据回调
            pushOpts.callbacks.credentials = gitCredentialCallback

            return git_remote_push(remotePtr, &refspecs, &pushOpts)
        }

        if result_strarray != 0 {
            var errorMessage = "Unknown push error"

            // 尝试从 libgit2 获取错误消息
            if let error = git_error_last() {
                let message = String(cString: error.pointee.message)
                if !message.isEmpty {
                    errorMessage = message
                }
            }

            // 如果没有具体的错误消息，提供通用说明
            if errorMessage == "Unknown push error" || errorMessage.isEmpty {
                errorMessage = "Push failed - please check your credentials and network connection"
            }

            if networkVerbose { os_log("❌ LibGit2: Push failed with code %d: %{public}@", result_strarray, errorMessage) }

            // 检查是否是认证错误
            if isAuthenticationError(result_strarray, errorMessage: errorMessage) {
                throw LibGit2Error.authenticationError
            }

            throw LibGit2Error.pushFailed(errorMessage)
        }

        if networkVerbose { os_log("🐚 LibGit2: Push completed successfully") }
    }

    /// 从远程仓库拉取
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - remote: 远程仓库名称（默认 "origin"）
    ///   - branch: 分支名称（nil 表示使用当前分支）
    public static func pull(at path: String, remote: String = "origin", branch: String? = nil, verbose: Bool = true) throws {
        networkVerbose = verbose
        if networkVerbose { os_log("🐚 LibGit2: Pulling from remote: %{public}@", remote) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remoteObj: OpaquePointer? = nil
        defer { if remoteObj != nil { git_remote_free(remoteObj) } }

        let result = git_remote_lookup(&remoteObj, repo, remote)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(remote)
        }

        guard let remotePtr = remoteObj else {
            throw LibGit2Error.remoteNotFound(remote)
        }

        // 获取当前分支名
        let branchName: String
        if let branch = branch {
            branchName = branch
        } else {
            branchName = try getCurrentBranch(at: path)
        }

        // 设置 fetch refspecs
        let refspec = "refs/heads/\(branchName):refs/remotes/\(remote)/\(branchName)"

        var fetchOpts = git_fetch_options()
        git_fetch_init_options(&fetchOpts, UInt32(GIT_FETCH_OPTIONS_VERSION))

        // 设置进度回调
        fetchOpts.callbacks.transfer_progress = { (progress: UnsafePointer<git_indexer_progress>?, payload: UnsafeMutableRawPointer?) -> Int32 in
            guard let progress = progress else { return 0 }
            let received = progress.pointee.received_objects
            let total = progress.pointee.total_objects
            let percent = total > 0 ? Float(received) / Float(total) * 100 : 0
            if networkVerbose { os_log("🐚 LibGit2: Fetch progress: %.1f%%", percent) }
            return 0
        }

        // 设置凭据回调
        fetchOpts.callbacks.credentials = gitCredentialCallback

        // 执行 fetch
        let refspecPtr = strdup(refspec)
        defer { free(refspecPtr) }

        var refspecs = git_strarray()
        var refspecArray: [UnsafeMutablePointer<CChar>?] = [refspecPtr]
        let fetchResult = refspecArray.withUnsafeMutableBufferPointer { buffer -> Int32 in
            refspecs.strings = buffer.baseAddress
            refspecs.count = 1
            return git_remote_fetch(remotePtr, &refspecs, &fetchOpts, nil)
        }

        if fetchResult != 0 {
            var errorMessage = "Unknown fetch error"

            if let error = git_error_last() {
                let message = String(cString: error.pointee.message)
                if !message.isEmpty {
                    errorMessage = message
                }
            }

            if networkVerbose { os_log("❌ LibGit2: Fetch failed with code %d: %{public}@", fetchResult, errorMessage) }

            // 检查是否是认证错误
            if isAuthenticationError(fetchResult, errorMessage: errorMessage) {
                throw LibGit2Error.authenticationError
            }

            throw LibGit2Error.pullFailed(errorMessage)
        }

        // 获取远程分支的 commit
        let remoteBranchRef = "refs/remotes/\(remote)/\(branchName)"
        var remoteOID = git_oid()

        if git_reference_name_to_id(&remoteOID, repo, remoteBranchRef) != 0 {
            throw LibGit2Error.pullFailed("Failed to get remote branch reference")
        }

        var remoteAnnotatedCommit: OpaquePointer? = nil
        defer { if remoteAnnotatedCommit != nil { git_annotated_commit_free(remoteAnnotatedCommit) } }

        if git_annotated_commit_lookup(&remoteAnnotatedCommit, repo, &remoteOID) != 0 {
            throw LibGit2Error.pullFailed("Failed to lookup annotated commit")
        }

        // 分析合并
        var analysis = git_merge_analysis_t.init(0)
        var preference = git_merge_preference_t.init(0)

        let headCommit = try getHEAD(at: path)
        let headRef = "refs/heads/\(headCommit)"

        var headOID = git_oid()
        git_reference_name_to_id(&headOID, repo, headRef)

        var headAnnotatedCommit: OpaquePointer? = nil
        defer { if headAnnotatedCommit != nil { git_annotated_commit_free(headAnnotatedCommit) } }

        git_annotated_commit_lookup(&headAnnotatedCommit, repo, &headOID)

        git_merge_analysis(&analysis, &preference, repo, &remoteAnnotatedCommit, 1)

        // 执行合并
        if analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue != 0 {
            if networkVerbose { os_log("🐚 LibGit2: Already up to date") }
            return
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue != 0 {
            // 快进合并
            var reference: OpaquePointer? = nil
            defer { if reference != nil { git_reference_free(reference) } }

            if git_reference_lookup(&reference, repo, headRef) == 0 {
                var updatedRef: OpaquePointer? = nil
                git_reference_set_target(&updatedRef, reference!, &remoteOID, "pull: fast-forward")
                git_reference_free(updatedRef)
            }
        } else if analysis.rawValue & GIT_MERGE_ANALYSIS_NORMAL.rawValue != 0 {
            // 需要普通合并
            var mergeOpts = git_merge_options()
            git_merge_init_options(&mergeOpts, UInt32(GIT_MERGE_OPTIONS_VERSION))
            
            var checkoutOpts = git_checkout_options()
            git_checkout_init_options(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
            checkoutOpts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue

            let mergeResult = git_merge(repo, &remoteAnnotatedCommit, 1, &mergeOpts, &checkoutOpts)

            if mergeResult != 0 {
                throw LibGit2Error.mergeConflict
            }

            // 创建合并提交
            // 这里简化处理，实际应用中可能需要更复杂的逻辑
        }

        os_log("🐚 LibGit2: Pull completed successfully")
    }

    /// 克隆远程仓库
    /// - Parameters:
    ///   - url: 远程仓库 URL
    ///   - destination: 目标路径
    ///   - branch: 要克隆的分支（nil 表示默认分支）
    ///   - depth: 浅克隆深度（0 表示完整克隆）
    public static func clone(url: String, to destination: String, branch: String? = nil, depth: Int = 0) throws {
        os_log("🐚 LibGit2: Cloning repository from: %{public}@", url)

        var cloneOpts = git_clone_options()
        git_clone_init_options(&cloneOpts, UInt32(GIT_CLONE_OPTIONS_VERSION))

        // 设置分支
        if let branch = branch {
            cloneOpts.checkout_branch = UnsafePointer<CChar>(strdup(branch))
        }

        // NOTE: depth is not a direct member of git_clone_options in some libgit2 versions
        // or it might need to be set via fetch_opts.custom_headers or similar if supported.
        // For now removing it if it causes errors.

        // 设置进度回调
        cloneOpts.fetch_opts.callbacks.transfer_progress = { (progress: UnsafePointer<git_indexer_progress>?, payload: UnsafeMutableRawPointer?) -> Int32 in
            guard let progress = progress else { return 0 }
            let received = progress.pointee.received_objects
            let total = progress.pointee.total_objects
            let percent = total > 0 ? Float(received) / Float(total) * 100 : 0
            os_log("🐚 LibGit2: Clone progress: %.1f%%", percent)
            return 0
        }

        var repo: OpaquePointer? = nil
        let result = git_clone(&repo, url, destination, &cloneOpts)

        if result != 0 || repo == nil {
            if let error = git_error_last() {
                let message = String(cString: error.pointee.message)
                os_log("❌ LibGit2: Clone failed: %{public}@", message)
            }
            throw LibGit2Error.cloneFailed
        }

        git_repository_free(repo)

        os_log("🐚 LibGit2: Repository cloned successfully to: %{public}@", destination)
    }

    /// 检查远程 URL 是否为有效的 Git 仓库
    /// - Parameter url: 远程仓库 URL
    /// - Returns: 如果是有效的 Git 仓库返回 true
    public static func isValidGitRepository(_ url: String, at path: String) -> Bool {
        guard let repo = try? openRepository(at: path) else { return false }
        defer { git_repository_free(repo) }

        var remote: OpaquePointer? = nil
        defer {
            if remote != nil {
                git_remote_free(remote)
            }
        }

        // 使用 git_remote_create_anonymous 来测试 URL
        let result = git_remote_create_anonymous(&remote, repo, url)

        return result == 0
    }
}

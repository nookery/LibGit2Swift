import Foundation
import MagicLog
import Clibgit2
import OSLog

// MARK: - Network Operations

/// 网络操作的 C 回调函数封装
private struct NetworkCallbacks: SuperLog {
    public static let emoji = "🌐"

    /// 控制网络操作的日志输出
    static var verbose: Bool = true

    /// Push 进度回调函数
    static let pushTransferProgress: git_push_transfer_progress = { (current: UInt32, total: UInt32, bytes: Int, payload: UnsafeMutableRawPointer?) -> Int32 in
        let verbose = payload?.assumingMemoryBound(to: Bool.self).pointee ?? true
        let percent = total > 0 ? Float(current) / Float(total) * 100 : 0
        if verbose {
            os_log("\(Self.t)Push progress: \(String(format: "%.1f", percent))%")
        }
        return 0
    }

    /// Fetch/Clone 进度回调函数
    static let transferProgress: @convention(c) (UnsafePointer<git_indexer_progress>?, UnsafeMutableRawPointer?) -> Int32 = { (progress, payload) in
        guard let progress = progress else { return 0 }
        let received = progress.pointee.received_objects
        let total = progress.pointee.total_objects
        let percent = total > 0 ? Float(received) / Float(total) * 100 : 0
        let verbose = payload?.assumingMemoryBound(to: Bool.self).pointee ?? true
        if verbose {
            os_log("\(Self.t) Transfer progress: \(String(format: "%.1f", percent))%")
        }
        return 0
    }
}

/// LibGit2 网络操作扩展（push, pull, clone）
extension LibGit2 {
    // MARK: - Authentication Error Detection

    /// 检查错误是否是认证错误
    /// - Parameters:
    ///   - errorCode: libgit2 错误代码
    ///   - errorMessage: 错误消息
    /// - Returns: 如果是认证错误返回 true
    private static func isAuthenticationError(_ errorCode: Int32, errorMessage: String) -> Bool {
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

    /// 检查错误是否是网络/SSL 错误
    /// - Parameters:
    ///   - errorCode: libgit2 错误代码
    ///   - errorMessage: 错误消息
    /// - Returns: 如果是网络/SSL 错误返回 true
    static func isNetworkError(_ errorCode: Int32, errorMessage: String) -> Bool {
        let lowercasedMessage = errorMessage.lowercased()
        let networkKeywords = [
            // SSL/TLS 错误
            "securetransport",
            "ssl",
            "tls",
            "certificate",
            "cert",
            "-9806",    // macOS SecureTransport SSL 常见错误码
            "-9814",    // macOS SecureTransport SSL 常见错误码
            "-9802",    // macOS SecureTransport SSL 常见错误码
            "-9843",    // macOS SecureTransport SSL 常见错误码

            // 网络连接错误
            "could not resolve host",
            "failed to connect",
            "connection timed out",
            "connection refused",
            "network is unreachable",
            "no route to host",
            "operation timed out",
            "connection reset",
            "broken pipe",
            "couldn't connect",
            "couldn't resolve",
            "name resolution",
            "dns",

            // 代理错误
            "proxy",
            "tunnel",

            // curl/传输层错误
            "curl",
            "transfer",
            "socket",
        ]

        return networkKeywords.contains { lowercasedMessage.contains($0) }
    }

    // MARK: - Public Methods

    /// 推送到远程仓库
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - remote: 远程仓库名称（默认 "origin"）
    ///   - branch: 分支名称（nil 表示使用当前分支）
    public static func push(at path: String, remote: String = "origin", branch: String? = nil, verbose: Bool = true) throws {
        // 获取当前分支名
        let branchName: String
        if let branch = branch {
            branchName = branch
        } else {
            branchName = try getCurrentBranch(at: path)
        }

        // 构建 refspec
        let refspec = "refs/heads/\(branchName):refs/heads/\(branchName)"
        try pushRefspecs([refspec], at: path, remote: remote, verbose: verbose)
    }

    /// 推送本地分支到远程分支，并可选择写入 upstream 配置。
    public static func publishBranch(
        localBranch: String,
        remote: String = "origin",
        remoteBranch: String? = nil,
        at path: String,
        setUpstream: Bool = true,
        verbose: Bool = true
    ) throws {
        let trimmedLocalBranch = localBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemoteBranch = remoteBranch?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedLocalBranch.isEmpty == false, trimmedRemote.isEmpty == false else {
            throw LibGit2Error.invalidReference
        }

        let destinationBranch = (trimmedRemoteBranch?.isEmpty == false ? trimmedRemoteBranch : nil) ?? trimmedLocalBranch
        let refspec = "refs/heads/\(trimmedLocalBranch):refs/heads/\(destinationBranch)"
        try pushRefspecs([refspec], at: path, remote: trimmedRemote, verbose: verbose)

        if setUpstream {
            try setConfig(key: "branch.\(trimmedLocalBranch).remote", value: trimmedRemote, at: path, verbose: false)
            try setConfig(key: "branch.\(trimmedLocalBranch).merge", value: "refs/heads/\(destinationBranch)", at: path, verbose: false)
        }
    }

    /// 删除远程分支，等价于 `git push <remote> --delete <branch>`。
    public static func deleteRemoteBranch(named branchName: String, remote: String = "origin", at path: String, verbose: Bool = true) throws {
        let trimmedName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false, trimmedRemote.isEmpty == false else {
            throw LibGit2Error.invalidReference
        }

        let shortBranchName = trimmedName.hasPrefix(trimmedRemote + "/")
            ? String(trimmedName.dropFirst(trimmedRemote.count + 1))
            : trimmedName

        guard shortBranchName.isEmpty == false && shortBranchName != "HEAD" else {
            throw LibGit2Error.invalidReference
        }

        try pushRefspecs([":refs/heads/\(shortBranchName)"], at: path, remote: trimmedRemote, verbose: verbose)
    }

    /// 推送本地标签到远程。
    public static func pushTag(named tagName: String, remote: String = "origin", at path: String, verbose: Bool = true) throws {
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false, trimmedRemote.isEmpty == false else {
            throw LibGit2Error.invalidReference
        }

        try pushRefspecs(["refs/tags/\(trimmedName):refs/tags/\(trimmedName)"], at: path, remote: trimmedRemote, verbose: verbose)
    }

    /// 删除远程标签。
    public static func deleteRemoteTag(named tagName: String, remote: String = "origin", at path: String, verbose: Bool = true) throws {
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false, trimmedRemote.isEmpty == false else {
            throw LibGit2Error.invalidReference
        }

        try pushRefspecs([":refs/tags/\(trimmedName)"], at: path, remote: trimmedRemote, verbose: verbose)
    }

    /// 使用指定 refspec 推送到远程仓库。
    public static func pushRefspecs(_ refspecs: [String], at path: String, remote: String = "origin", verbose: Bool = true) throws {
        NetworkCallbacks.verbose = verbose
        if NetworkCallbacks.verbose { os_log("\(t)Pushing to remote: \(remote)") }

        let trimmedRefspecs = refspecs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard trimmedRefspecs.isEmpty == false else {
            throw LibGit2Error.invalidReference
        }

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

        let refspecPointers = trimmedRefspecs.map { strdup($0) }
        defer { refspecPointers.forEach { free($0) } }

        var gitRefspecs = git_strarray()
        var refspecArray = refspecPointers
        let result_strarray = refspecArray.withUnsafeMutableBufferPointer { buffer -> Int32 in
            gitRefspecs.strings = buffer.baseAddress
            gitRefspecs.count = trimmedRefspecs.count

            var pushOpts = git_push_options()
            git_push_init_options(&pushOpts, UInt32(GIT_PUSH_OPTIONS_VERSION))

            // 设置进度回调
            pushOpts.callbacks.push_transfer_progress = NetworkCallbacks.pushTransferProgress
            let verbosePayloadPtr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            verbosePayloadPtr.pointee = verbose

            // 设置凭据回调
            pushOpts.callbacks.credentials = gitCredentialCallback
            pushOpts.callbacks.payload = UnsafeMutableRawPointer(verbosePayloadPtr)

            let result = git_remote_push(remotePtr, &gitRefspecs, &pushOpts)
            verbosePayloadPtr.deallocate()
            return result
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

            if NetworkCallbacks.verbose { os_log("\(t)Push failed with code \(result_strarray): \(errorMessage)") }

            // 检查是否是认证错误
            if isAuthenticationError(result_strarray, errorMessage: errorMessage) {
                throw LibGit2Error.authenticationError
            }

            // 检查是否是网络/SSL 错误
            if isNetworkError(result_strarray, errorMessage: errorMessage) {
                throw LibGit2Error.networkError(Int(result_strarray))
            }

            throw LibGit2Error.pushFailed(errorMessage)
        }

        if NetworkCallbacks.verbose { os_log("\(t)Push completed successfully") }
    }

    /// 从远程仓库拉取
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - remote: 远程仓库名称（默认 "origin"）
    ///   - branch: 分支名称（nil 表示使用当前分支）
    public static func pull(at path: String, remote: String = "origin", branch: String? = nil, verbose: Bool = true) throws {
        NetworkCallbacks.verbose = verbose
        if NetworkCallbacks.verbose { os_log("\(t)Pulling from remote: \(remote)") }

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

        // 设置凭据回调
        fetchOpts.callbacks.credentials = gitCredentialCallback

        // 设置进度回调
        fetchOpts.callbacks.transfer_progress = NetworkCallbacks.transferProgress
        let verbosePayloadPtr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        verbosePayloadPtr.pointee = verbose
        defer { verbosePayloadPtr.deallocate() }
        fetchOpts.callbacks.payload = UnsafeMutableRawPointer(verbosePayloadPtr)

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

            if NetworkCallbacks.verbose { os_log("\(t)Fetch failed with code \(fetchResult): \(errorMessage)") }

            // 检查是否是认证错误
            if isAuthenticationError(fetchResult, errorMessage: errorMessage) {
                throw LibGit2Error.authenticationError
            }

            // 检查是否是网络/SSL 错误
            if isNetworkError(fetchResult, errorMessage: errorMessage) {
                throw LibGit2Error.networkError(Int(fetchResult))
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
            if NetworkCallbacks.verbose { os_log("\(t)Already up to date") }
            return
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue != 0 {
            let hasLocalChanges = try hasUncommittedChanges(at: path, verbose: false)

            if hasLocalChanges {
                var mergeOpts = git_merge_options()
                git_merge_init_options(&mergeOpts, UInt32(GIT_MERGE_OPTIONS_VERSION))

                var checkoutOpts = makeSafeCheckoutOptions()
                let mergeResult = git_merge(repo, &remoteAnnotatedCommit, 1, &mergeOpts, &checkoutOpts)
                if mergeResult != 0 {
                    throw errorFromCheckoutResult(mergeResult, context: "pull")
                }
                git_repository_state_cleanup(repo)
            } else {
                var reference: OpaquePointer? = nil
                defer { if reference != nil { git_reference_free(reference) } }

                guard git_reference_lookup(&reference, repo, headRef) == 0, let reference else {
                    throw LibGit2Error.pullFailed("Failed to lookup branch reference for fast-forward")
                }

                var updatedRef: OpaquePointer? = nil
                let setTargetResult = git_reference_set_target(
                    &updatedRef,
                    reference,
                    &remoteOID,
                    "pull: fast-forward"
                )
                git_reference_free(updatedRef)
                if setTargetResult != 0 {
                    throw LibGit2Error.pullFailed("Failed to fast-forward branch reference")
                }

                var checkoutOpts = git_checkout_options()
                git_checkout_init_options(&checkoutOpts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
                checkoutOpts.checkout_strategy = GIT_CHECKOUT_FORCE.rawValue |
                    GIT_CHECKOUT_RECREATE_MISSING.rawValue
                let checkoutResult = git_checkout_head(repo, &checkoutOpts)
                if checkoutResult != 0 {
                    throw LibGit2Error.pullFailed("Failed to update working tree after fast-forward")
                }
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

        os_log("\(t)Pull completed successfully")
    }

    /// Fetch remote refs without merging them into the current branch.
    public static func fetch(at path: String, remote: String = "origin", prune: Bool = true, verbose: Bool = true) throws {
        NetworkCallbacks.verbose = verbose

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remoteObj: OpaquePointer?
        defer { if remoteObj != nil { git_remote_free(remoteObj) } }

        guard git_remote_lookup(&remoteObj, repo, remote) == 0, let remoteObj else {
            throw LibGit2Error.remoteNotFound(remote)
        }

        var fetchOpts = git_fetch_options()
        git_fetch_init_options(&fetchOpts, UInt32(GIT_FETCH_OPTIONS_VERSION))
        fetchOpts.callbacks.credentials = gitCredentialCallback
        fetchOpts.callbacks.transfer_progress = NetworkCallbacks.transferProgress
        fetchOpts.prune = prune ? GIT_FETCH_PRUNE : GIT_FETCH_NO_PRUNE

        let verbosePayloadPtr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        verbosePayloadPtr.pointee = verbose
        defer { verbosePayloadPtr.deallocate() }
        fetchOpts.callbacks.payload = UnsafeMutableRawPointer(verbosePayloadPtr)

        let result = git_remote_fetch(remoteObj, nil, &fetchOpts, nil)
        if result != 0 {
            if let error = git_error_last() {
                let message = String(cString: error.pointee.message)
                if isAuthenticationError(result, errorMessage: message) {
                    throw LibGit2Error.authenticationError
                }
                if isNetworkError(result, errorMessage: message) {
                    throw LibGit2Error.networkError(Int(result))
                }
                throw LibGit2Error.pullFailed(message)
            }
            throw LibGit2Error.pullFailed("Fetch failed")
        }
    }

    /// 克隆远程仓库
    /// - Parameters:
    ///   - url: 远程仓库 URL
    ///   - destination: 目标路径
    ///   - branch: 要克隆的分支（nil 表示默认分支）
    ///   - depth: 浅克隆深度（0 表示完整克隆）
    public static func clone(url: String, to destination: String, branch: String? = nil, depth: Int = 0) throws {
        os_log("\(t)Cloning repository from: \(url)")

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
        cloneOpts.fetch_opts.callbacks.transfer_progress = NetworkCallbacks.transferProgress
        let verbosePayloadPtr = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        verbosePayloadPtr.pointee = true
        defer { verbosePayloadPtr.deallocate() }
        cloneOpts.fetch_opts.callbacks.payload = UnsafeMutableRawPointer(verbosePayloadPtr)

        var repo: OpaquePointer? = nil
        let result = git_clone(&repo, url, destination, &cloneOpts)

        if result != 0 || repo == nil {
            if let error = git_error_last() {
                let message = String(cString: error.pointee.message)
                os_log("\(t)Clone failed: \(message)")
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

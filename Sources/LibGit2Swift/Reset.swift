import Foundation
import Clibgit2
import OSLog

/// LibGit2 重置操作扩展
extension LibGit2 {
    /// 重置到指定提交
    /// - Parameters:
    ///   - commitHash: 提交哈希（nil 表示 HEAD）
    ///   - mode: 重置模式（"soft", "mixed", "hard"）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func reset(to commitHash: String?, mode: String, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Resetting to %{public}@ with mode: %{public}@", commitHash ?? "HEAD", mode) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var targetOID = git_oid()

        if let commitHash = commitHash {
            guard git_oid_fromstr(&targetOID, commitHash) == 0 else {
                throw LibGit2Error.invalidValue
            }
        } else {
            if git_reference_name_to_id(&targetOID, repo, "HEAD") != 0 {
                throw LibGit2Error.cannotGetHEAD
            }
        }

        var commit: OpaquePointer? = nil
        defer { if commit != nil { git_commit_free(commit) } }

        guard git_commit_lookup(&commit, repo, &targetOID) == 0,
              let commitPtr = commit else {
            throw LibGit2Error.invalidValue
        }

        let resetType: git_reset_t
        switch mode.lowercased() {
        case "soft":
            resetType = GIT_RESET_SOFT
        case "mixed":
            resetType = GIT_RESET_MIXED
        case "hard":
            resetType = GIT_RESET_HARD
        default:
            resetType = GIT_RESET_MIXED
        }

        let result = git_reset(repo, commitPtr, resetType, nil)

        if result != 0 {
            throw LibGit2Error.checkoutFailed(commitHash ?? "HEAD")
        }

        if verbose { os_log("🐚 LibGit2: Reset completed") }
    }

    /// 软重置（保留工作区和暂存区变更）
    /// - Parameters:
    ///   - commitHash: 提交哈希（nil 表示 HEAD）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func resetSoft(to commitHash: String?, at path: String, verbose: Bool = true) throws {
        try reset(to: commitHash, mode: "soft", at: path, verbose: verbose)
    }

    /// 混合重置（保留工作区变更，清空暂存区）
    /// - Parameters:
    ///   - commitHash: 提交哈希（nil 表示 HEAD）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func resetMixed(to commitHash: String?, at path: String, verbose: Bool = true) throws {
        try reset(to: commitHash, mode: "mixed", at: path, verbose: verbose)
    }

    /// 硬重置（丢弃所有变更）
    /// - Parameters:
    ///   - commitHash: 提交哈希（nil 表示 HEAD）
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func resetHard(to commitHash: String?, at path: String, verbose: Bool = true) throws {
        try reset(to: commitHash, mode: "hard", at: path, verbose: verbose)
    }

    /// 重置指定文件（从暂存区移除）
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func resetFile(_ filePath: String, at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Resetting file: %{public}@", filePath) }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var index: OpaquePointer? = nil
        defer { if index != nil { git_index_free(index) } }

        guard git_repository_index(&index, repo) == 0 else {
            throw LibGit2Error.cannotGetIndex
        }

        // 从 index 中移除文件
        let result = git_index_remove_bypath(index!, filePath)

        if result != 0 {
            // 文件可能不在 index 中
            if verbose { os_log("⚠️ LibGit2: File not in index: %{public}@", filePath) }
        }

        git_index_write(index!)

        if verbose { os_log("🐚 LibGit2: File reset: %{public}@", filePath) }
    }

    /// 重置所有暂存区文件
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func resetStaged(at path: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Resetting all staged files") }

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var index: OpaquePointer? = nil
        defer { if index != nil { git_index_free(index) } }

        guard git_repository_index(&index, repo) == 0 else {
            throw LibGit2Error.cannotGetIndex
        }

        // 清空 index
        git_index_clear(index!)
        git_index_write(index!)

        if verbose { os_log("🐚 LibGit2: All staged files reset") }
    }

    /// 重置到指定提交（保留部分文件）
    /// - Parameters:
    ///   - commitHash: 提交哈希
    ///   - paths: 要保留的文件路径列表
    ///   - resetMode: 重置模式
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    static func resetToCommitKeepingFiles(_ commitHash: String, keeping paths: [String], mode resetMode: String, at repoPath: String, verbose: Bool = true) throws {
        if verbose { os_log("🐚 LibGit2: Resetting to %{public}@ keeping files", commitHash) }

        let repo = try openRepository(at: repoPath)
        defer { git_repository_free(repo) }

        var targetOID = git_oid()
        guard git_oid_fromstr(&targetOID, commitHash) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var commit: OpaquePointer? = nil
        defer { if commit != nil { git_commit_free(commit) } }

        guard git_commit_lookup(&commit, repo, &targetOID) == 0,
              let commitPtr = commit else {
            throw LibGit2Error.invalidValue
        }

        var stringPointers: [UnsafeMutablePointer<CChar>?] = paths.map { strdup($0) }
        defer {
            for ptr in stringPointers {
                free(ptr)
            }
        }

        let result = stringPointers.withUnsafeMutableBufferPointer { buffer -> Int32 in
            var strarray = git_strarray(strings: buffer.baseAddress, count: buffer.count)
            return git_reset_default(repo, commitPtr, &strarray)
        }

        if result != 0 {
            throw LibGit2Error.checkoutFailed(commitHash)
        }

        if verbose { os_log("🐚 LibGit2: Reset completed keeping specified files") }
    }
}

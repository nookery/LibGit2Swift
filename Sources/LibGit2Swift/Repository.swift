import Foundation
import Clibgit2
import OSLog

/// LibGit2 仓库操作扩展
extension LibGit2 {
    /// 创建一个新的 Git 仓库
    /// - Parameter path: 仓库路径
    /// - Returns: 仓库指针
    public static func createRepository(at path: String) throws -> OpaquePointer {
        var repo: OpaquePointer? = nil
        let result = git_repository_init(&repo, path, 0)

        if result != 0 {
            throw LibGit2Error.repositoryNotFound(path)
        }

        guard let repository = repo else {
            throw LibGit2Error.invalidRepository
        }

        return repository
    }

    /// 检查指定路径是否是 Git 仓库
    /// - Parameter path: 要检查的路径
    /// - Returns: 如果是 Git 仓库返回 true，否则返回 false
    /// 检查指定路径是否是 Git 仓库
    /// - Parameter path: 要检查的路径
    /// - Returns: 如果是 Git 仓库返回 true，否则返回 false
    public static func isGitRepository(at path: String) -> Bool {
        var repo: OpaquePointer? = nil
        let result = git_repository_open_ext(&repo, path, GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil)

        if repo != nil {
            git_repository_free(repo)
        }

        return result == 0
    }

    /// 获取仓库根目录
    /// - Parameter path: 仓库中的任意路径
    /// - Returns: 仓库根目录路径，如果不是仓库则返回 nil
    public static func repositoryRoot(at path: String) -> String? {
        var repo: OpaquePointer? = nil
        defer {
            if repo != nil { git_repository_free(repo) }
        }

        let result = git_repository_open_ext(&repo, path, GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil)
        if result != 0, repo == nil {
            return nil
        }

        if let repository = repo {
            let workdir = git_repository_workdir(repository)
            if let pathPtr = workdir {
                return String(cString: pathPtr)
            }
        }

        return nil
    }

    /// 获取仓库的 HEAD 引用
    /// - Parameter path: 仓库路径
    /// - Returns: HEAD 引用名称或 commit hash（如果 detached）
    public static func getHEAD(at path: String) throws -> String {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var head: OpaquePointer? = nil
        defer {
            if head != nil { git_reference_free(head) }
        }

        let result = git_repository_head(&head, repo)

        if result == GIT_ENOTFOUND.rawValue {
            // 仓库是空的（还没有 commit）
            throw LibGit2Error.invalidRepository
        } else if result != 0 {
            throw LibGit2Error.cannotGetHEAD
        }

        guard let reference = head else {
            throw LibGit2Error.invalidReference
        }

        // 检查是否是符号引用（分支）
        if git_reference_type(reference) == GIT_REFERENCE_SYMBOLIC {
            let target = git_reference_symbolic_target(reference)
            if let targetPtr = target {
                let targetName = String(cString: targetPtr)
                // "refs/heads/main" -> "main"
                return targetName.replacingOccurrences(of: "refs/heads/", with: "")
            }
        }

        // HEAD detached，返回 commit hash
        if let headPtr = head {
            let oid = git_reference_target(headPtr)
            if let oidPtr = oid {
                return oidToString(oidPtr.pointee)
            }
        }

        throw LibGit2Error.invalidReference
    }

    /// 获取当前分支名称
    /// - Parameter path: 仓库路径
    /// - Returns: 当前分支名称，如果 HEAD detached 返回 commit hash
    public static func getCurrentBranch(at path: String) throws -> String {
        return try getHEAD(at: path)
    }

    /// 检查 HEAD 是否 detached
    /// - Parameter path: 仓库路径
    /// - Returns: 如果 HEAD detached 返回 true
    public static func isHEADDetached(at path: String) throws -> Bool {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        return git_repository_head_detached(repo) == 1
    }

    /// 获取仓库状态（是否为空仓库）
    /// - Parameter path: 仓库路径
    /// - Returns: 如果是空仓库返回 true
    public static func isEmptyRepository(at path: String) throws -> Bool {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        return git_repository_is_empty(repo) == 1
    }

    /// 获取仓库路径
    /// - Parameter path: 仓库中的任意路径
    /// - Returns: 仓库的 .git 目录路径
    public static func gitDirectory(at path: String) throws -> String {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let gitDir = git_repository_path(repo)
        if let pathPtr = gitDir {
            return String(cString: pathPtr)
        }

        throw LibGit2Error.repositoryNotFound(path)
    }
}

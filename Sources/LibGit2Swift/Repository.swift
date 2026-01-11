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

        // 使用默认标志，允许向上搜索
        let result = git_repository_open_ext(&repo, path, 0, nil)
        if result != 0, repo == nil {
            return nil
        }

        if let repository = repo {
            let workdir = git_repository_workdir(repository)
            if let pathPtr = workdir {
                let workdirPath = String(cString: pathPtr)
                // 移除结尾的斜杠
                return workdirPath.hasSuffix("/") ? String(workdirPath.dropLast()) : workdirPath
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

        // 首先尝试直接读取HEAD文件
        let gitDir = try gitDirectory(at: path)
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")

        if let headContent = try? String(contentsOfFile: headPath, encoding: .utf8) {
            let trimmedContent = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.hasPrefix("ref: ") {
                let refName = String(trimmedContent.dropFirst(5))
                // "refs/heads/main" -> "main"
                if refName.hasPrefix("refs/heads/") {
                    let branchName = String(refName.dropFirst(11))
                    // 检查分支引用是否存在
                    let repo = try openRepository(at: path)
                    defer { git_repository_free(repo) }

                    var reference: OpaquePointer? = nil
                    let lookupResult = git_reference_lookup(&reference, repo, refName)
                    if lookupResult == 0 {
                        git_reference_free(reference)
                        return branchName
                    } else {
                        // 分支引用不存在，抛出错误
                        throw LibGit2Error.invalidReference
                    }
                }
                return refName
            }
        }

        // 回退到libgit2 API
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
        let refType = git_reference_type(reference)
        if refType == GIT_REFERENCE_SYMBOLIC {
            let target = git_reference_symbolic_target(reference)
            if let targetPtr = target {
                let targetName = String(cString: targetPtr)
                // "refs/heads/main" -> "main"
                let branchName = targetName.replacingOccurrences(of: "refs/heads/", with: "")
                print("🐚 LibGit2: HEAD is symbolic ref to branch: \(branchName)")
                return branchName
            }
        }

        // HEAD detached 或直接引用，返回 commit hash
        if let headPtr = head {
            let oid = git_reference_target(headPtr)
            if let oidPtr = oid {
                let hash = oidToString(oidPtr.pointee)
                print("🐚 LibGit2: HEAD is detached at commit: \(hash)")
                return hash
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

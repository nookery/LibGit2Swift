import Foundation
import Clibgit2
import OSLog


/// LibGit2 远程仓库操作扩展
extension LibGit2 {
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

                let pushURLPtr = git_remote_pushurl(remotePtr)
                let pushURL = pushURLPtr != nil ? String(cString: pushURLPtr!) : nil

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
    public static func addRemote(name: String, url: String, at path: String) throws {
        os_log("🐚 LibGit2: Adding remote: %{public}@ -> %{public}@", name, url)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remote: OpaquePointer? = nil
        defer { if remote != nil { git_remote_free(remote) } }

        let result = git_remote_create(&remote, repo, name, url)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        os_log("🐚 LibGit2: Remote added: %{public}@", name)
    }

    /// 删除远程仓库
    /// - Parameters:
    ///   - name: 远程仓库名称
    ///   - path: 仓库路径
    public static func removeRemote(name: String, at path: String) throws {
        os_log("🐚 LibGit2: Removing remote: %{public}@", name)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        let result = git_remote_delete(repo, name)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        os_log("🐚 LibGit2: Remote removed: %{public}@", name)
    }

    /// 设置远程仓库 URL
    /// - Parameters:
    ///   - name: 远程仓库名称
    ///   - url: 新的 URL
    ///   - path: 仓库路径
    public static func setRemoteURL(name: String, url: String, at path: String) throws {
        os_log("🐚 LibGit2: Setting remote URL: %{public}@ -> %{public}@", name, url)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var remote: OpaquePointer? = nil
        defer { if remote != nil { git_remote_free(remote) } }

        let result = git_remote_lookup(&remote, repo, name)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        guard let remotePtr = remote else {
            throw LibGit2Error.remoteNotFound(name)
        }

        let setResult = git_remote_set_url(repo, name, url)

        if setResult != 0 {
            throw LibGit2Error.remoteNotFound(name)
        }

        os_log("🐚 LibGit2: Remote URL updated: %{public}@", name)
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
    public static func renameRemote(oldName: String, to newName: String, at path: String) throws {
        os_log("🐚 LibGit2: Renaming remote: %{public}@ -> %{public}@", oldName, newName)

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var problems = git_strarray()
        defer { git_strarray_free(&problems) }

        let result = git_remote_rename(&problems, repo, oldName, newName)

        if result != 0 {
            throw LibGit2Error.remoteNotFound(oldName)
        }

        os_log("🐚 LibGit2: Remote renamed")
    }
}

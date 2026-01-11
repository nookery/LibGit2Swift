import Foundation
import Clibgit2
import OSLog


/// LibGit2 差异操作扩展
extension LibGit2 {
    /// 获取差异文件列表
    /// - Parameters:
    ///   - path: 仓库路径
    ///   - staged: 是否获取已暂存的变更（false = 工作区变更）
    /// - Returns: 差异文件列表
    public static func getDiffFileList(at path: String, staged: Bool = false) throws -> [GitDiffFile] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var diff: OpaquePointer? = nil
        defer { if diff != nil { git_diff_free(diff) } }

        if staged {
            // 获取已暂存的变更 (index vs HEAD)
            var index: OpaquePointer? = nil
            defer { if index != nil { git_index_free(index) } }

            guard git_repository_index(&index, repo) == 0 else {
                throw LibGit2Error.cannotGetIndex
            }

            var tree: OpaquePointer? = nil
            defer { if tree != nil { git_tree_free(tree) } }

            // 获取 HEAD tree
            var headCommit: OpaquePointer? = nil
            defer { if headCommit != nil { git_commit_free(headCommit) } }

            var headOID = git_oid()

            // 检查是否有 HEAD（可能是空仓库）
            if git_reference_name_to_id(&headOID, repo, "HEAD") == 0 {
                git_commit_lookup(&headCommit, repo, &headOID)

                if let commit = headCommit {
                    git_commit_tree(&tree, commit)
                }
            }

            // 如果没有 HEAD，创建空 diff
            if tree == nil {
                var diffOpts = git_diff_options()
                git_diff_init_options(&diffOpts, UInt32(GIT_DIFF_OPTIONS_VERSION))
                git_diff_tree_to_tree(&diff, repo, nil, nil, &diffOpts)
            } else {
                git_diff_tree_to_index(&diff, repo, tree, index, nil)
            }
        } else {
            // 获取工作区变更 (index vs workdir)
            var index: OpaquePointer? = nil
            defer { if index != nil { git_index_free(index) } }

            guard git_repository_index(&index, repo) == 0 else {
                throw LibGit2Error.cannotGetIndex
            }

            git_diff_index_to_workdir(&diff, repo, index, nil)
        }

        guard let diffPtr = diff else {
            return []
        }

        return parseDiffFiles(diffPtr, repo: repo, path: path)
    }

    /// 获取指定文件的差异内容
    /// - Parameters:
    ///   - file: 文件路径
    ///   - path: 仓库路径
    ///   - staged: 是否获取已暂存的变更
    /// - Returns: 差异内容字符串
    public static func getFileDiff(for file: String, at path: String, staged: Bool = false) throws -> String {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var diff: OpaquePointer? = nil
        defer { if diff != nil { git_diff_free(diff) } }

        if staged {
            var index: OpaquePointer? = nil
            defer { if index != nil { git_index_free(index) } }

            guard git_repository_index(&index, repo) == 0 else {
                throw LibGit2Error.cannotGetIndex
            }

            var tree: OpaquePointer? = nil
            defer { if tree != nil { git_tree_free(tree) } }

            var headCommit: OpaquePointer? = nil
            defer { if headCommit != nil { git_commit_free(headCommit) } }

            var headOID = git_oid()

            if git_reference_name_to_id(&headOID, repo, "HEAD") == 0 {
                git_commit_lookup(&headCommit, repo, &headOID)

                if let commit = headCommit {
                    git_commit_tree(&tree, commit)
                }
            }

            if tree != nil {
                var diffOpts = git_diff_options()
                git_diff_init_options(&diffOpts, UInt32(GIT_DIFF_OPTIONS_VERSION))
                let filePathCStr = strdup(file)
                var strings: [UnsafeMutablePointer<CChar>?] = [filePathCStr]
                strings.withUnsafeMutableBufferPointer { buffer in
                    diffOpts.pathspec.strings = buffer.baseAddress
                    diffOpts.pathspec.count = 1
                }
                
                defer {
                    free(filePathCStr)
                }

                git_diff_tree_to_index(&diff, repo, tree, index, &diffOpts)
            }
        } else {
            var index: OpaquePointer? = nil
            defer { if index != nil { git_index_free(index) } }

            guard git_repository_index(&index, repo) == 0 else {
                throw LibGit2Error.cannotGetIndex
            }

            var diffOpts = git_diff_options()
            git_diff_init_options(&diffOpts, UInt32(GIT_DIFF_OPTIONS_VERSION))
            let filePathCStr = strdup(file)
            var strings: [UnsafeMutablePointer<CChar>?] = [filePathCStr]
            strings.withUnsafeMutableBufferPointer { buffer in
                diffOpts.pathspec.strings = buffer.baseAddress
                diffOpts.pathspec.count = 1
            }

            defer {
                free(filePathCStr)
            }

            git_diff_index_to_workdir(&diff, repo, index, &diffOpts)
        }

        guard let diffPtr = diff else {
            return ""
        }

        // 生成 patch
        var patch: OpaquePointer? = nil
        defer { if patch != nil { git_patch_free(patch) } }

        let count = git_diff_num_deltas(diffPtr)
        var patchText = ""

        for i in 0..<count {
            if git_patch_from_diff(&patch, diffPtr, i) == 0, let patchPtr = patch {
                var buf = git_buf()
                defer { git_buf_dispose(&buf) }

                if git_patch_to_buf(&buf, patchPtr) == 0 {
                    let content = String(cString: buf.ptr)
                    patchText += content
                }
            }
        }

        return patchText
    }

    /// 获取指定提交修改的文件列表
    /// - Parameters:
    ///   - commitHash: 提交哈希
    ///   - path: 仓库路径
    /// - Returns: 差异文件列表
    public static func getCommitDiffFiles(atCommit commitHash: String, at path: String) throws -> [GitDiffFile] {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        // 获取指定commit
        var oid = git_oid()
        guard git_oid_fromstr(&oid, commitHash) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var commit: OpaquePointer? = nil
        defer { if commit != nil { git_commit_free(commit) } }

        guard git_commit_lookup(&commit, repo, &oid) == 0, let commitPtr = commit else {
            throw LibGit2Error.invalidValue
        }

        // 获取该commit的tree
        var commitTree: OpaquePointer? = nil
        defer { if commitTree != nil { git_tree_free(commitTree) } }

        guard git_commit_tree(&commitTree, commitPtr) == 0 else {
            throw LibGit2Error.invalidValue
        }

        // 获取父commit（用于比较）
        let parentCount = git_commit_parentcount(commitPtr)
        var diff: OpaquePointer? = nil
        defer { if diff != nil { git_diff_free(diff) } }

        if parentCount == 0 {
            // 初始提交，与空树比较
            var diffOpts = git_diff_options()
            git_diff_init_options(&diffOpts, UInt32(GIT_DIFF_OPTIONS_VERSION))
            git_diff_tree_to_tree(&diff, repo, nil, commitTree, &diffOpts)
        } else {
            // 获取第一个父commit
            var parentOid = git_commit_parent_id(commitPtr, 0).pointee

            var parentCommit: OpaquePointer? = nil
            defer { if parentCommit != nil { git_commit_free(parentCommit) } }

            guard git_commit_lookup(&parentCommit, repo, &parentOid) == 0,
                  let parentCommitPtr = parentCommit else {
                throw LibGit2Error.invalidValue
            }

            var parentTree: OpaquePointer? = nil
            defer { if parentTree != nil { git_tree_free(parentTree) } }

            guard git_commit_tree(&parentTree, parentCommitPtr) == 0 else {
                throw LibGit2Error.invalidValue
            }

            // 比较父commit和当前commit的tree
            git_diff_tree_to_tree(&diff, repo, parentTree, commitTree, nil)
        }

        guard let diffPtr = diff else {
            return []
        }

        return parseDiffFiles(diffPtr, repo: repo, path: path)
    }

    /// 获取两个提交之间的差异
    /// - Parameters:
    ///   - from: 起始提交哈希
    ///   - to: 结束提交哈希
    ///   - path: 仓库路径
    /// - Returns: 差异内容字符串
    public static func getDiffBetweenCommits(from: String, to: String, at path: String) throws -> String {
        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var fromOid = git_oid()
        var toOid = git_oid()

        guard git_oid_fromstr(&fromOid, from) == 0,
              git_oid_fromstr(&toOid, to) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var fromCommit: OpaquePointer? = nil
        var toCommit: OpaquePointer? = nil
        defer {
            if fromCommit != nil { git_commit_free(fromCommit) }
            if toCommit != nil { git_commit_free(toCommit) }
        }

        guard git_commit_lookup(&fromCommit, repo, &fromOid) == 0,
              git_commit_lookup(&toCommit, repo, &toOid) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var fromTree: OpaquePointer? = nil
        var toTree: OpaquePointer? = nil
        defer {
            if fromTree != nil { git_tree_free(fromTree) }
            if toTree != nil { git_tree_free(toTree) }
        }

        guard git_commit_tree(&fromTree, fromCommit!) == 0,
              git_commit_tree(&toTree, toCommit!) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var diff: OpaquePointer? = nil
        defer { if diff != nil { git_diff_free(diff) } }

        git_diff_tree_to_tree(&diff, repo, fromTree, toTree, nil)

        guard let diffPtr = diff else {
            return ""
        }

        // 生成 patch
        var patch: OpaquePointer? = nil
        defer { if patch != nil { git_patch_free(patch) } }

        let count = git_diff_num_deltas(diffPtr)
        var patchText = ""

        for i in 0..<count {
            if git_patch_from_diff(&patch, diffPtr, i) == 0, let patchPtr = patch {
                var buf = git_buf()
                defer { git_buf_dispose(&buf) }

                if git_patch_to_buf(&buf, patchPtr) == 0 {
                    let content = String(cString: buf.ptr)
                    patchText += content
                }
            }
        }

        return patchText
    }

    /// 获取指定提交中的文件内容
    /// - Parameters:
    ///   - commitHash: 提交哈希
    ///   - filePath: 文件路径
    ///   - repoPath: 仓库路径
    /// - Returns: 文件内容字符串
    public static func getFileContent(atCommit commitHash: String, file filePath: String, at repoPath: String) throws -> String {
        let repo = try openRepository(at: repoPath)
        defer { git_repository_free(repo) }

        var oid = git_oid()
        guard git_oid_fromstr(&oid, commitHash) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var commit: OpaquePointer? = nil
        defer { if commit != nil { git_commit_free(commit) } }

        guard git_commit_lookup(&commit, repo, &oid) == 0, let commitPtr = commit else {
            throw LibGit2Error.invalidValue
        }

        var tree: OpaquePointer? = nil
        defer { if tree != nil { git_tree_free(tree) } }

        guard git_commit_tree(&tree, commitPtr) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var treeEntry: OpaquePointer? = nil

        if git_tree_entry_bypath(&treeEntry, tree, filePath) == 0, let entry = treeEntry {
            defer { git_tree_entry_free(entry) }

            var blob: OpaquePointer? = nil
            defer { if blob != nil { git_blob_free(blob) } }

            let entryOid = git_tree_entry_id(entry)

            if git_blob_lookup(&blob, repo, entryOid) == 0, let blobPtr = blob {
                let contentPtr = git_blob_rawcontent(blobPtr)
                let size = git_blob_rawsize(blobPtr)

                if let ptr = contentPtr {
                    let data = Data(bytes: ptr, count: Int(size))
                    if let content = String(data: data, encoding: .utf8) {
                        return content
                    }
                }
            }
        }

        throw LibGit2Error.invalidValue
    }

    /// 获取指定提交中文件变更的前后内容
    /// - Parameters:
    ///   - commitHash: 提交哈希
    ///   - filePath: 文件路径
    ///   - repoPath: 仓库路径
    /// - Returns: 元组 (before: 修改前的内容, after: 修改后的内容)
    public static func getFileContentChange(atCommit commitHash: String, file filePath: String, at repoPath: String) throws -> (before: String?, after: String?) {
        let repo = try openRepository(at: repoPath)
        defer { git_repository_free(repo) }

        // 获取指定commit
        var oid = git_oid()
        guard git_oid_fromstr(&oid, commitHash) == 0 else {
            throw LibGit2Error.invalidValue
        }

        var commit: OpaquePointer? = nil
        defer { if commit != nil { git_commit_free(commit) } }

        guard git_commit_lookup(&commit, repo, &oid) == 0, let commitPtr = commit else {
            throw LibGit2Error.invalidValue
        }

        // 获取该commit的父commit（用于获取修改前的内容）
        let parentCount = git_commit_parentcount(commitPtr)
        var beforeContent: String? = nil

        if parentCount > 0 {
            // 有父commit，从父commit获取文件内容
            var parentOid = git_commit_parent_id(commitPtr, 0).pointee

            var parentCommit: OpaquePointer? = nil
            defer { if parentCommit != nil { git_commit_free(parentCommit) } }

            if git_commit_lookup(&parentCommit, repo, &parentOid) == 0, let parentCommitPtr = parentCommit {
                do {
                    beforeContent = try getFileContent(atCommit: git_oid_tostr(&parentOid)!, file: filePath, at: repoPath)
                } catch {
                    // 文件可能在父commit中不存在，这是正常情况
                    beforeContent = nil
                }
            }
        } else {
            // 初始提交，没有修改前内容
            beforeContent = nil
        }

        // 从当前commit获取文件内容（修改后的内容）
        var afterContent: String? = nil
        do {
            afterContent = try getFileContent(atCommit: commitHash, file: filePath, at: repoPath)
        } catch {
            // 文件被删除，这是正常情况
            afterContent = nil
        }

        return (beforeContent, afterContent)
    }

    /// 获取未提交文件的前后内容
    /// - Parameters:
    ///   - filePath: 文件路径
    ///   - repoPath: 仓库路径
    /// - Returns: 元组 (before: HEAD中的内容, after: 工作区中的内容)
    public static func getUncommittedFileContentChange(for filePath: String, at repoPath: String) throws -> (before: String?, after: String?) {
        let repo = try openRepository(at: repoPath)
        defer { git_repository_free(repo) }

        // 获取HEAD commit（用于获取修改前的内容）
        var beforeContent: String? = nil

        var headOID = git_oid()
        if git_reference_name_to_id(&headOID, repo, "HEAD") == 0 {
            let headCommitHash = String(cString: git_oid_tostr(&headOID))
            do {
                beforeContent = try getFileContent(atCommit: headCommitHash, file: filePath, at: repoPath)
            } catch {
                // 文件在HEAD中不存在（新文件），这是正常情况
                beforeContent = nil
            }
        }

        // 从工作区获取文件内容（修改后的内容）
        var afterContent: String? = nil
        let fullPath = URL(fileURLWithPath: repoPath).appendingPathComponent(filePath).path

        if FileManager.default.fileExists(atPath: fullPath) {
            do {
                afterContent = try String(contentsOfFile: fullPath, encoding: .utf8)
            } catch {
                afterContent = nil
            }
        } else {
            // 文件被删除
            afterContent = nil
        }

        return (beforeContent, afterContent)
    }

    // MARK: - 私有辅助方法

    /// 解析差异文件列表
    private static func parseDiffFiles(_ diff: OpaquePointer, repo: OpaquePointer, path: String) -> [GitDiffFile] {
        var files: [GitDiffFile] = []
        let count = git_diff_num_deltas(diff)

        for i in 0..<count {
            guard let delta = git_diff_get_delta(diff, i) else { continue }

            let deltaType = delta.pointee.status
            let changeType = convertDeltaStatus(deltaType)

            let oldPath = delta.pointee.old_file.path
            let newPath = delta.pointee.new_file.path

            let filePath: String
            if deltaType == GIT_DELTA_ADDED {
                filePath = String(cString: newPath!)
            } else if deltaType == GIT_DELTA_DELETED {
                filePath = String(cString: oldPath!)
            } else if oldPath != nil && newPath != nil {
                let oldPathStr = String(cString: oldPath!)
                let newPathStr = String(cString: newPath!)
                filePath = oldPathStr == newPathStr ? oldPathStr : "\(oldPathStr) -> \(newPathStr)"
            } else {
                filePath = String(cString: oldPath ?? newPath!)
            }

            // 获取 diff 内容
            var diffContent = ""
            var patch: OpaquePointer? = nil
            defer { if patch != nil { git_patch_free(patch) } }

            if git_patch_from_diff(&patch, diff, i) == 0, let patchPtr = patch {
                var buf = git_buf()
                defer { git_buf_dispose(&buf) }

                if git_patch_to_buf(&buf, patchPtr) == 0 {
                    diffContent = String(cString: buf.ptr)
                }
            }

            files.append(GitDiffFile(
                id: filePath,
                file: filePath,
                changeType: changeType,
                diff: diffContent
            ))
        }

        return files
    }

    /// 转换 delta 状态为字符串标识
    private static func convertDeltaStatus(_ status: git_delta_t) -> String {
        switch status {
        case GIT_DELTA_ADDED:
            return "A"
        case GIT_DELTA_DELETED:
            return "D"
        case GIT_DELTA_MODIFIED:
            return "M"
        case GIT_DELTA_RENAMED:
            return "R"
        case GIT_DELTA_COPIED:
            return "C"
        case GIT_DELTA_IGNORED:
            return "I"
        case GIT_DELTA_UNTRACKED:
            return "?"
        case GIT_DELTA_TYPECHANGE:
            return "T"
        default:
            return " "
        }
    }
}

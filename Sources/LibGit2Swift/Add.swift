import Foundation
import Clibgit2
import OSLog

/// LibGit2 添加文件操作扩展
extension LibGit2 {
    /// 添加文件到暂存区
    /// - Parameters:
    ///   - files: 要添加的文件路径列表（空数组表示添加所有变更）
    ///   - path: 仓库路径
    public static func addFiles(_ files: [String], at path: String) throws {
        os_log("🐚 LibGit2: Adding files to staging area")

        let repo = try openRepository(at: path)
        defer { git_repository_free(repo) }

        var index: OpaquePointer? = nil
        defer { if index != nil { git_index_free(index) } }

        guard git_repository_index(&index, repo) == 0,
              let indexPtr = index else {
            throw LibGit2Error.cannotGetIndex
        }

        // 如果 files 为空，添加所有变更
        if files.isEmpty {
            // 获取所有未跟踪和已修改的文件
            var statusOpts = git_status_options()
            git_status_init_options(&statusOpts, UInt32(GIT_STATUS_OPTIONS_VERSION))
            statusOpts.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue |
                              GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue

            var statusList: OpaquePointer? = nil
            defer { if statusList != nil { git_status_list_free(statusList) } }

            if git_status_list_new(&statusList, repo, &statusOpts) == 0 {
                let count = git_status_list_entrycount(statusList!)

                for i in 0..<count {
                    if let entry = git_status_byindex(statusList!, i) {
                        let status = entry.pointee.status
                        let statusRaw = status.rawValue
                        // 只处理工作区的变更
                        if statusRaw & GIT_STATUS_WT_NEW.rawValue != 0 ||
                           statusRaw & GIT_STATUS_WT_MODIFIED.rawValue != 0 ||
                           statusRaw & GIT_STATUS_WT_DELETED.rawValue != 0 ||
                           statusRaw & GIT_STATUS_WT_TYPECHANGE.rawValue != 0 {

                            let pathPtr = entry.pointee.index_to_workdir?.pointee.old_file.path
                                       ?? entry.pointee.head_to_index?.pointee.new_file.path

                            if let filePath = pathPtr {
                                let result = git_index_add_bypath(indexPtr, filePath)
                                if result != 0 {
                                    os_log("⚠️ LibGit2: Failed to add file: %{public}@", String(cString: filePath))
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // 添加指定的文件
            for file in files {
                let result = git_index_add_bypath(indexPtr, file)
                if result != 0 {
                    throw LibGit2Error.addFileFailed(file)
                }
                os_log("🐚 LibGit2: Added file: %{public}@", file)
            }
        }

        // 写入 index
        let writeResult = git_index_write(indexPtr)
        if writeResult != 0 {
            throw LibGit2Error.cannotGetIndex
        }

        os_log("🐚 LibGit2: Files added successfully")
    }

    /// 添加单个文件到暂存区
    /// - Parameters:
    ///   - file: 文件路径
    ///   - path: 仓库路径
    static func addFile(_ file: String, at path: String) throws {
        try addFiles([file], at: path)
    }

    /// 添加所有变更到暂存区
    /// - Parameter path: 仓库路径
    static func addAll(at path: String) throws {
        try addFiles([], at: path)
    }
}

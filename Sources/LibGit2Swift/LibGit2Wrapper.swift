import Clibgit2
import Foundation
import MagicLog
import OSLog

/// libgit2 C 库的 Swift 封装
/// 提供类型安全的接口和自动内存管理
/// libgit2 C 库的 Swift 封装
/// 提供类型安全的接口和自动内存管理
public class LibGit2: SuperLog {
    public static let emoji = "🗂️"
    /// 初始化 libgit2（应用启动时调用一次）
    public static func initialize() {
        git_libgit2_init()

        // 注意：git_libgit2_opts 是可变参数函数，在 Swift 中不可直接调用
        // 大多数情况下 libgit2 会自动找到正确的 HOME 目录
        // 如果需要设置 HOMEDIR，可以通过环境变量实现
        os_log("\(Self.t)✅ LibGit2 initialized")
    }

    /// 清理 libgit2（应用退出时调用）
    public static func shutdown() {
        git_libgit2_shutdown()
    }

    /// 获取 libgit2 最后一次发生的错误描述
    private static func lastError() -> String {
        if let error = git_error_last() {
            return String(cString: error.pointee.message)
        }
        return "No specific libgit2 error message"
    }

    /// 从指定仓库路径获取配置值
    /// - Parameters:
    ///   - key: 配置键（如 "user.name"）
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    /// - Returns: 配置值
    public static func getConfig(key: String, at repoPath: String, verbose: Bool) throws -> String {
        if verbose { os_log("\(t)Getting config for key: \(key) at path: \(repoPath)") }

        var repo: OpaquePointer?
        var config: OpaquePointer?
        var snapshot: OpaquePointer?
        var outPtr: UnsafePointer<CChar>?

        defer {
            if snapshot != nil { git_config_free(snapshot) }
            if config != nil { git_config_free(config) }
            if repo != nil { git_repository_free(repo) }
        }

        // 1. 尝试通过仓库获取配置
        let openResult = git_repository_open(&repo, repoPath)
        if openResult == 0, let repository = repo {
            if git_repository_config(&config, repository) == 0, let configuration = config {
                // 在 libgit2 1.x 中，获取字符串必须在 snapshot 上操作
                if git_config_snapshot(&snapshot, configuration) == 0, let configSnapshot = snapshot {
                    let getResult = git_config_get_string(&outPtr, configSnapshot, key)
                    if getResult == 0, let cString = outPtr {
                        let value = String(cString: cString)
                        if verbose { os_log("\(LibGit2.t)Config found in repo: \(key) = \(value)") }
                        return value
                    }
                    if verbose { os_log("\(LibGit2.t)Key not found in repo snapshot, code: \(getResult)") }
                    // 清理 snapshot 以便后面 fallback 使用
                    git_config_free(snapshot)
                    snapshot = nil
                }
            }
        } else {
            if verbose { os_log("\(LibGit2.t)Could not open repo at \(repoPath), trying default config") }
        }

        // 2. Fallback: 直接读取默认全局配置
        if verbose { os_log("\(LibGit2.t)Attempting fallback to default (global) config for key: \(key)") }
        var defaultConfig: OpaquePointer?
        defer { if defaultConfig != nil { git_config_free(defaultConfig) } }

        if git_config_open_default(&defaultConfig) == 0, let configuration = defaultConfig {
            if git_config_snapshot(&snapshot, configuration) == 0, let configSnapshot = snapshot {
                let getResult = git_config_get_string(&outPtr, configSnapshot, key)
                if getResult == 0, let cString = outPtr {
                    let value = String(cString: cString)
                    if verbose { os_log("\(LibGit2.t)Config found in default/global config: \(key) = \(value)") }
                    return value
                }
                if verbose { os_log("\(LibGit2.t)Key not found in default snapshot: \(lastError())") }
            }
        }

        throw LibGit2Error.configKeyNotFound(key)
    }

    /// 设置配置值
    /// - Parameters:
    ///   - key: 配置键（如 "user.name"）
    ///   - value: 配置值
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func setConfig(key: String, value: String, at repoPath: String, verbose: Bool) throws {
        if verbose { os_log("\(LibGit2.t)Setting config for key: \(key) at path: \(repoPath)") }

        let repo = try openRepository(at: repoPath)
        defer { git_repository_free(repo) }

        var config: OpaquePointer?
        defer { if config != nil { git_config_free(config) } }

        guard git_repository_config(&config, repo) == 0,
              let configuration = config else {
            throw LibGit2Error.configNotFound
        }

        let result: Int32
        if value.isEmpty {
            // 空值表示删除配置
            result = git_config_delete_entry(configuration, key)
            // 删除不存在的配置不应该抛出错误
            if result != 0 && result != GIT_ENOTFOUND.rawValue {
                throw LibGit2Error.configKeyNotFound(key)
            }
        } else {
            result = git_config_set_string(configuration, key, value)
            if result != 0 {
                throw LibGit2Error.configKeyNotFound(key)
            }
        }

        if verbose { os_log("\(LibGit2.t)Config set successfully: \(key) = \(value)") }
    }

    /// 获取用户配置（用户名和邮箱）
    /// - Parameters:
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    /// - Returns: (用户名, 邮箱)元组
    public static func getUserConfig(at repoPath: String, verbose: Bool) throws -> (name: String, email: String) {
        let name = try getConfig(key: "user.name", at: repoPath, verbose: verbose)
        let email = try getConfig(key: "user.email", at: repoPath, verbose: verbose)
        return (name, email)
    }

    /// 设置用户配置
    /// - Parameters:
    ///   - name: 用户名
    ///   - email: 用户邮箱
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func setUserConfig(name: String, email: String, at repoPath: String, verbose: Bool) throws {
        try setConfig(key: "user.name", value: name, at: repoPath, verbose: verbose)
        try setConfig(key: "user.email", value: email, at: repoPath, verbose: verbose)
    }

    /// 获取用户名
    /// - Parameters:
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志
    /// - Returns: 用户名
    public static func getUserName(at repoPath: String, verbose: Bool) throws -> String {
        return try getConfig(key: "user.name", at: repoPath, verbose: verbose)
    }

    /// 获取用户邮箱
    /// - Parameters:
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    /// - Returns: 用户邮箱
    public static func getUserEmail(at repoPath: String, verbose: Bool = true) throws -> String {
        return try getConfig(key: "user.email", at: repoPath, verbose: verbose)
    }

    /// 设置用户名
    /// - Parameters:
    ///   - name: 用户名
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func setUserName(name: String, at repoPath: String, verbose: Bool = true) throws {
        try setConfig(key: "user.name", value: name, at: repoPath, verbose: verbose)
    }

    /// 设置用户邮箱
    /// - Parameters:
    ///   - email: 用户邮箱
    ///   - repoPath: 仓库路径
    ///   - verbose: 是否输出详细日志，默认为true
    public static func setUserEmail(email: String, at repoPath: String, verbose: Bool = true) throws {
        try setConfig(key: "user.email", value: email, at: repoPath, verbose: verbose)
    }

    // MARK: - 辅助函数

    /// 将 git_oid 转换为字符串
    public static func oidToString(_ oid: git_oid) -> String {
        var mutableOid = oid
        var buffer = [Int8](repeating: 0, count: Int(GIT_OID_HEXSZ) + 1)
        git_oid_tostr(&buffer, Int(GIT_OID_HEXSZ) + 1, &mutableOid)
        return String(cString: &buffer)
    }

    /// 打开仓库
    public static func openRepository(at path: String) throws -> OpaquePointer {
        var repo: OpaquePointer?
        let result = git_repository_open(&repo, path)

        if result != 0 {
            throw LibGit2Error.repositoryNotFound(path)
        }

        guard let repository = repo else {
            throw LibGit2Error.invalidRepository
        }

        return repository
    }
}

/// libgit2 错误类型
public enum LibGit2Error: Error, LocalizedError {
    // 现有错误
    case repositoryNotFound(String)
    case configNotFound
    case configKeyNotFound(String)
    case invalidValue
    case cannotGetIndex
    case cannotWriteTree
    case cannotGetHEAD
    case cannotCreateRevwalk
    case cannotGetStatus
    case nothingToCommit
    case commitFailed
    case addFileFailed(String)
    case checkoutFailed(String)
    case remoteNotFound(String)
    case pushFailed(String) // 修改：携带详细错误消息
    case pullFailed(String) // 修改：携带详细错误消息
    case cloneFailed
    case mergeConflict
    case invalidRepository
    case invalidReference
    case networkError(Int)
    case authenticationError

    public var errorDescription: String? {
        switch self {
        case let .repositoryNotFound(path):
            return "Git repository not found at: \(path)"
        case .configNotFound:
            return "Failed to get git configuration"
        case let .configKeyNotFound(key):
            return "Configuration key not found: \(key)"
        case .invalidValue:
            return "Invalid configuration value"
        case .cannotGetHEAD:
            return "Cannot get HEAD reference"
        case .cannotGetIndex:
            return "Cannot get repository index"
        case .cannotCreateRevwalk:
            return "Cannot create revision walker"
        case .cannotGetStatus:
            return "Cannot get repository status"
        case .cannotWriteTree:
            return "Cannot write tree object"
        case .nothingToCommit:
            return "Nothing to commit"
        case .commitFailed:
            return "Failed to create commit"
        case let .addFileFailed(file):
            return "Failed to add file: \(file)"
        case let .checkoutFailed(branch):
            return "Failed to checkout branch: \(branch)"
        case let .remoteNotFound(remote):
            return "Remote not found: \(remote)"
        case let .pushFailed(message):
            return message // 修改：使用详细错误消息
        case let .pullFailed(message):
            return message // 修改：使用详细错误消息
        case .cloneFailed:
            return "Failed to clone repository"
        case .mergeConflict:
            return "Merge conflict detected"
        case .invalidRepository:
            return "Invalid repository"
        case .invalidReference:
            return "Invalid reference"
        case let .networkError(code):
            return "Network error occurred: \(code)"
        case .authenticationError:
            return "Authentication failed"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .authenticationError:
            return "Please check your credentials and try again"
        case .networkError:
            return "Please check your network connection"
        case .mergeConflict:
            return "Please resolve conflicts before continuing"
        default:
            return nil
        }
    }
}

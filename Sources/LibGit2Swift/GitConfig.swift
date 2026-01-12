import Foundation
import MagicLog
import OSLog

/// Git 配置辅助类
/// 使用 libgit2 读取 Git 配置信息
public class GitConfig: SuperLog {
    public static let emoji = "🔑"

    /// 从指定仓库路径获取用户名
    public static func getUserName(at path: String, verbose: Bool = true) throws -> String {
        if verbose { os_log("\(emoji) Getting user name at path: \(path)") }
        return try LibGit2.getConfig(key: "user.name", at: path, verbose: verbose)
    }

    /// 从指定仓库路径获取用户邮箱
    public static func getUserEmail(at path: String, verbose: Bool = true) throws -> String {
        if verbose { os_log("\(emoji) Getting user email at path: \(path)") }
        return try LibGit2.getConfig(key: "user.email", at: path, verbose: verbose)
    }
}

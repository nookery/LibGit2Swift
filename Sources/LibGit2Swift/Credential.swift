import Foundation
import Clibgit2
import OSLog
import Security

// MARK: - Credential Manager

/// 管理Git凭据的辅助类
public class CredentialManager {
    static let logger = OSLog(subsystem: "com.coffic.LibGit2Swift", category: "Credential")

    /// 从 macOS Keychain 获取指定URL的Git凭据
    /// - Parameter urlString: Git远程URL
    /// - Returns: 用户名和密码元组，如果未找到则返回nil
    public static func getCredentialFromKeychain(for urlString: String) -> (username: String, password: String)? {
        // 从URL中提取host
        guard let url = URL(string: urlString) else {
            os_log("❌ Invalid URL: %{public}@", log: logger, type: .error, urlString)
            return nil
        }

        let host = url.host ?? urlString
        let `protocol` = url.scheme ?? "https"

        os_log("🔑 Looking up credentials for host: %{public}@", log: logger, type: .info, host)

        // 构建Keychain查询
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: `protocol`,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let item = result as? [String: Any],
              let username = item[kSecAttrAccount as String] as? String,
              let passwordData = item[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            os_log("❌ No credentials found in Keychain for host: %{public}@", log: logger, type: .error, host)
            return nil
        }

        os_log("✅ Found credentials in Keychain for user: %{public}@", log: logger, type: .info, username)
        return (username, password)
    }

    /// 尝试从git-credential-*获取凭据（作为fallback）
    /// - Parameter urlString: Git远程URL
    /// - Returns: 用户名和密码元组，如果未找到则返回nil
    public static func getCredentialFromGitHelper(for urlString: String) -> (username: String, password: String)? {
        // 实现git credential fill协议
        // 这是一个fallback方案，如果Keychain中没有找到凭据

        os_log("🔍 Attempting to use git credential helper for: %{public}@", log: logger, type: .info, urlString)

        // TODO: 实现与git credential helper的通信
        // 这需要通过Process调用git credential fill

        return nil
    }

    /// 为指定的URL获取凭据
    /// - Parameter urlString: Git远程URL
    /// - Returns: 用户名和密码元组，如果未找到则返回nil
    public static func getCredential(for urlString: String) -> (username: String, password: String)? {
        // 首先尝试从Keychain获取
        if let credential = getCredentialFromKeychain(for: urlString) {
            return credential
        }

        // Fallback到git credential helper
        return getCredentialFromGitHelper(for: urlString)
    }

    /// 将凭据保存到Keychain
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    ///   - urlString: Git远程URL
    public static func saveCredentialToKeychain(username: String, password: String, for urlString: String) {
        guard let url = URL(string: urlString) else {
            os_log("❌ Invalid URL for saving credential: %{public}@", log: logger, type: .error, urlString)
            return
        }

        let host = url.host ?? urlString
        let `protocol` = url.scheme ?? "https"

        let passwordData = password.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: `protocol`,
            kSecAttrAccount as String: username,
            kSecValueData as String: passwordData
        ]

        // 先删除旧的凭据（如果存在）
        SecItemDelete(query as CFDictionary)

        // 添加新凭据
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            os_log("✅ Credentials saved to Keychain for user: %{public}@", log: logger, type: .info, username)
        } else {
            os_log("❌ Failed to save credentials to Keychain: %d", log: logger, type: .error, status)
        }
    }
}

// MARK: - Credential Callback Context

/// 用于在credential回调中传递上下文信息
private struct CredentialContext {
    let urlString: String
    var lastError: Int32 = 0
}

// MARK: - C Callback Function

/// libgit2的credential回调函数
/// 这个函数会被libgit2调用以获取认证凭据
public let gitCredentialCallback: @convention(c) (
    UnsafeMutablePointer<UnsafeMutablePointer<git_credential>?>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UInt32,
    UnsafeMutableRawPointer?
) -> Int32 = { out, url, username_from_url, allowed_types, payload in
    guard let urlPointer = url else {
        return -1
    }

    let urlString = String(cString: urlPointer)
    os_log("🔐 Credential callback invoked for: %{public}@", log: CredentialManager.logger, type: .info, urlString)
    os_log("🔐 Allowed credential types: %{public}@", log: CredentialManager.logger, type: .debug, allowed_types)

    // 从Keychain或git helper获取凭据
    guard let (username, password) = CredentialManager.getCredential(for: urlString) else {
        os_log("❌ No credentials found for: %{public}@", log: CredentialManager.logger, type: .error, urlString)
        os_log("💡 Hint: You can add credentials using 'git credential approve' or Keychain Access", log: CredentialManager.logger, type: .info)
        return Int32(GIT_EUSER.rawValue)
    }

    os_log("✅ Found credentials for user: %{public}@", log: CredentialManager.logger, type: .info, username)

    // 根据allowed_types选择合适的凭据类型
    if allowed_types & GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue != 0 {
        os_log("🔑 Using user/pass plaintext authentication", log: CredentialManager.logger, type: .debug)

        // 使用明文用户名/密码
        let result = username.withCString { usernamePtr in
            password.withCString { passwordPtr in
                git_credential_userpass_plaintext_new(
                    out,
                    usernamePtr,
                    passwordPtr
                )
            }
        }

        if result == 0 {
            os_log("✅ Successfully created userpass credential for: %{public}@", log: CredentialManager.logger, type: .info, username)
            return 0
        } else {
            os_log("❌ Failed to create credential, error code: %d", log: CredentialManager.logger, type: .error, result)
            return Int32(GIT_EUSER.rawValue)
        }
    }

    if allowed_types & GIT_CREDENTIAL_SSH_KEY.rawValue != 0 {
        // TODO: 实现SSH密钥认证
        os_log("⚠️ SSH key authentication requested but not yet implemented", log: CredentialManager.logger, type: .error)
    }

    os_log("❌ No supported credential type found in allowed_types: %u", log: CredentialManager.logger, type: .error, allowed_types)
    return Int32(GIT_EUSER.rawValue)
}

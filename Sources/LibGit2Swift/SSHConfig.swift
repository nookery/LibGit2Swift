import Foundation
import OSLog

// MARK: - SSH Configuration Parser

/// SSH 配置解析器
/// 用于解析 ~/.ssh/config 文件并提取主机相关的配置
public struct SSHConfig {

    /// SSH 主机配置
    public struct HostConfig {
        public let host: String
        public let hostName: String?
        public let port: Int?
        public let user: String?
        public let identityFile: String?
        public let preferredAuthentications: String?

        public init(
            host: String,
            hostName: String? = nil,
            port: Int? = nil,
            user: String? = nil,
            identityFile: String? = nil,
            preferredAuthentications: String? = nil
        ) {
            self.host = host
            self.hostName = hostName
            self.port = port
            self.user = user
            self.identityFile = identityFile
            self.preferredAuthentications = preferredAuthentications
        }

        /// 获取完整的 SSH URL（包含端口）
        public func getFullSSHURL(originalURL: String) -> String {
            // 如果原始 URL 已经是 ssh:// 格式，直接返回
            if originalURL.hasPrefix("ssh://") {
                return originalURL
            }

            // 检查是否需要重写端口
            let effectivePort = port ?? 22

            // 从原始 URL 提取用户和路径
            // 格式: user@host:path 或 git@host:path
            let pattern = "^([^@]+)@([^:]+):(.+)$"

            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: originalURL, range: NSRange(originalURL.startIndex..., in: originalURL)) {

                let user = originalURL[Range(match.range(at: 1), in: originalURL)!]
                let host = originalURL[Range(match.range(at: 2), in: originalURL)!]
                let path = originalURL[Range(match.range(at: 3), in: originalURL)!]

                // 使用配置中的 HostName（如果有），否则使用原始 host
                let effectiveHost = hostName ?? String(host)

                // 如果端口不是标准 22，使用 ssh:// 格式
                if effectivePort != 22 {
                    return "ssh://\(user)@\(effectiveHost):\(effectivePort)/\(path)"
                } else {
                    // 端口是 22，保持原始格式
                    if hostName != nil {
                        return "\(user)@\(effectiveHost):\(path)"
                    }
                    return originalURL
                }
            }

            // 无法解析，返回原始 URL
            return originalURL
        }
    }

    /// 从 ~/.ssh/config 读取并解析 SSH 配置
    /// - Returns: 主机配置数组
    public static func parseSSHConfig() -> [HostConfig] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.ssh/config"

        guard FileManager.default.fileExists(atPath: configPath) else {
            os_log("⚠️ SSH config file not found at: \(configPath)")
            return []
        }

        do {
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            return parseConfig(content: content)
        } catch {
            os_log("⚠️ Failed to read SSH config: \(error)")
            return []
        }
    }

    /// 查找匹配特定主机的配置
    /// - Parameter hostname: 主机名（例如 codebowl.juhe.cn）
    /// - Returns: 匹配的配置，如果没有找到返回 nil
    public static func findConfig(for hostname: String) -> HostConfig? {
        let configs = parseSSHConfig()

        // 首先查找精确匹配
        if let exactMatch = configs.first(where: { $0.host == hostname }) {
            return exactMatch
        }

        // 然后查找通配符匹配
        for config in configs {
            // 检查是否是通配符（包含 * 或 ?）
            if config.host.contains("*") || config.host.contains("?") {
                // 简单的通配符匹配（只支持 *）
                let pattern = config.host.replacingOccurrences(of: ".", with: "\\.")
                                       .replacingOccurrences(of: "*", with: ".*")
                if let regex = try? NSRegularExpression(pattern: "^\(pattern)$") {
                    let range = NSRange(hostname.startIndex..., in: hostname)
                    if regex.firstMatch(in: hostname, range: range) != nil {
                        return config
                    }
                }
            }
        }

        return nil
    }

    /// 解析 SSH 配置文件内容
    private static func parseConfig(content: String) -> [HostConfig] {
        var configs: [HostConfig] = []
        var currentHost: String?
        var currentHostName: String?
        var currentPort: Int?
        var currentUser: String?
        var currentIdentityFile: String?
        var currentPreferredAuthentications: String?

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // 跳过空行和注释
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            // 检查是否是 Host 行
            if trimmedLine.lowercased().hasPrefix("host") {
                // 保存之前的配置（如果有）
                if let host = currentHost {
                    configs.append(HostConfig(
                        host: host,
                        hostName: currentHostName,
                        port: currentPort,
                        user: currentUser,
                        identityFile: currentIdentityFile,
                        preferredAuthentications: currentPreferredAuthentications
                    ))
                }

                // 解析新的 Host
                let hostValue = trimmedLine.dropFirst(4).trimmingCharacters(in: .whitespaces)
                currentHost = hostValue
                currentHostName = nil
                currentPort = nil
                currentUser = nil
                currentIdentityFile = nil
                currentPreferredAuthentications = nil
            } else if let host = currentHost {
                // 解析配置项
                let parts = trimmedLine.split(separator: " ", maxSplits: 1)
                         .map { $0.trimmingCharacters(in: .whitespaces) }

                if parts.count >= 2 {
                    let key = parts[0].lowercased()
                    let value = parts[1]

                    switch key {
                    case "hostname":
                        currentHostName = value
                    case "port":
                        currentPort = Int(value)
                    case "user":
                        currentUser = value
                    case "identityfile":
                        // 展开 ~ 为完整路径
                        if value.hasPrefix("~") {
                            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                            currentIdentityFile = value.replacingOccurrences(of: "~", with: homeDir)
                        } else {
                            currentIdentityFile = value
                        }
                    case "preferredauthentications":
                        currentPreferredAuthentications = value
                    default:
                        break
                    }
                }
            }
        }

        // 保存最后一个配置
        if let host = currentHost {
            configs.append(HostConfig(
                host: host,
                hostName: currentHostName,
                port: currentPort,
                user: currentUser,
                identityFile: currentIdentityFile,
                preferredAuthentications: currentPreferredAuthentications
            ))
        }

        return configs
    }
}

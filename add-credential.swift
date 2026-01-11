#!/usr/bin/env swift

import Foundation
import Security

// 简单的工具来添加 GitHub 凭据到 macOS Keychain
// 使用方法: swift add-credential.swift <username> <password>

func addCredentialToKeychain(username: String, password: String, server: String = "github.com", protocol: String = "https") {
    let passwordData = password.data(using: .utf8)!

    let query: [String: Any] = [
        kSecClass as String: kSecClassInternetPassword,
        kSecAttrServer as String: server,
        kSecAttrProtocol as String: `protocol`,
        kSecAttrAccount as String: username,
        kSecValueData as String: passwordData
    ]

    // 先删除旧的凭据（如果存在）
    SecItemDelete(query as CFDictionary)

    // 添加新凭据
    let status = SecItemAdd(query as CFDictionary, nil)

    if status == errSecSuccess {
        print("✅ Successfully added credentials to Keychain")
        print("   Server: \(server)")
        print("   Username: \(username)")
        print("   Protocol: \(`protocol`)")
    } else {
        print("❌ Failed to add credentials to Keychain")
        print("   Error code: \(status)")
        exit(1)
    }
}

func printUsage() {
    print("Usage: swift add-credential.swift <username> <password> [server]")
    print("")
    print("Example:")
    print("  swift add-credential.swift myusername mytoken")
    print("  swift add-credential.swift myusername mytoken github.com")
    print("")
    print("Note: For GitHub, use your GitHub username and a Personal Access Token as password")
}

// 检查命令行参数
guard CommandLine.arguments.count >= 3 else {
    printUsage()
    exit(1)
}

let username = CommandLine.arguments[1]
let password = CommandLine.arguments[2]
let server = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : "github.com"

// 添加凭据
addCredentialToKeychain(username: username, password: password, server: server)

print("\n💡 You can now use Git push/pull without entering credentials!")
print("💡 To remove credentials later, use: security delete-internet-password -s \(server)")

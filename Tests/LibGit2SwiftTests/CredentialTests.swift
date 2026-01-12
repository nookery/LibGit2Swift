import Foundation
import Clibgit2
@testable import LibGit2Swift
import XCTest
import Security

/// Credential 相关功能的测试
final class CredentialTests: LibGit2SwiftTestCase {
    // MARK: - Credential Manager Tests

    func testGetCredentialFromKeychain() throws {
        // 跳过在 CI 环境中的测试
        try XCTSkipIf(isRunningInCI(), "Keychain tests skipped in CI environment")

        // 保存测试凭据到 Keychain
        let testURL = "https://github.com/test/test-repo.git"
        let testUsername = "test_user_\(UUID().uuidString.prefix(8))"
        let testPassword = "test_password_\(UUID().uuidString)"

        // 保存凭据
        CredentialManager.saveCredentialToKeychain(
            username: testUsername,
            password: testPassword,
            for: testURL
        )

        // 读取凭据
        let retrieved = CredentialManager.getCredentialFromKeychain(for: testURL)

        // 验证凭据
        XCTAssertNotNil(retrieved, "Should retrieve credential from Keychain")
        XCTAssertEqual(retrieved?.username, testUsername, "Username should match")
        XCTAssertEqual(retrieved?.password, testPassword, "Password should match")

        // 清理：删除测试凭据
        deleteKeychainCredential(for: testURL)
    }

    func testGetCredentialFromKeychainNotFound() throws {
        // 跳过在 CI 环境中的测试
        try XCTSkipIf(isRunningInCI(), "Keychain tests skipped in CI environment")

        // 测试不存在的凭据
        let nonExistentURL = "https://nonexistent.example.com/test.git"
        let retrieved = CredentialManager.getCredentialFromKeychain(for: nonExistentURL)

        // 应该返回 nil
        XCTAssertNil(retrieved, "Should return nil for non-existent credential")
    }

    func testSaveCredentialToKeychain() throws {
        // 跳过在 CI 环境中的测试
        try XCTSkipIf(isRunningInCI(), "Keychain tests skipped in CI environment")

        let testURL = "https://github.com/test/save-test.git"
        let testUsername = "save_test_user"
        let testPassword = "save_test_password"

        // 保存凭据
        CredentialManager.saveCredentialToKeychain(
            username: testUsername,
            password: testPassword,
            for: testURL
        )

        // 验证凭据已保存
        let retrieved = CredentialManager.getCredentialFromKeychain(for: testURL)
        XCTAssertNotNil(retrieved, "Credential should be saved")
        XCTAssertEqual(retrieved?.username, testUsername)

        // 清理
        deleteKeychainCredential(for: testURL)
    }

    func testGetCredentialIntegration() throws {
        // 跳过在 CI 环境中的测试
        try XCTSkipIf(isRunningInCI(), "Keychain tests skipped in CI environment")

        // 测试完整的 getCredential 流程
        let testURL = "https://gitlab.com/test/integration-test.git"
        let testUsername = "integration_user"
        let testPassword = "integration_password"

        // 保存凭据
        CredentialManager.saveCredentialToKeychain(
            username: testUsername,
            password: testPassword,
            for: testURL
        )

        // 通过 getCredential 获取
        let retrieved = CredentialManager.getCredential(for: testURL)

        XCTAssertNotNil(retrieved, "Should retrieve credential through getCredential")
        XCTAssertEqual(retrieved?.username, testUsername)
        XCTAssertEqual(retrieved?.password, testPassword)

        // 清理
        deleteKeychainCredential(for: testURL)
    }

    func testCredentialWithInvalidURL() {
        // 测试无效的 URL
        let invalidURL = "not-a-valid-url"
        let retrieved = CredentialManager.getCredentialFromKeychain(for: invalidURL)

        // 应该返回 nil
        XCTAssertNil(retrieved, "Should return nil for invalid URL")
    }

    func testCredentialCallbackWithNoCredential() throws {
        // 跳过在 CI 环境中的测试
        try XCTSkipIf(isRunningInCI(), "Keychain tests skipped in CI environment")

        // 测试当没有凭据时的回调行为
        let testURL = "https://nonexistent-domain-12345.com/test/no-credential-test.git"

        // 确保没有这个凭据
        deleteKeychainCredential(for: testURL)

        // 调用回调函数
        let urlPointer = (testURL as NSString).utf8String
        var credentialPtr: UnsafeMutablePointer<git_credential>?

        let result = withUnsafeMutablePointer(to: &credentialPtr) { ptr in
            gitCredentialCallback(
                ptr,
                urlPointer,
                nil,
                GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue,
                nil
            )
        }

        // 应该返回错误（没有找到凭据）
        XCTAssertEqual(result, Int32(GIT_EUSER.rawValue), "Should return GIT_EUSER when no credential found")

        // 清理（如果测试失败可能创建了凭据）
        deleteKeychainCredential(for: testURL)
    }

    // MARK: - Helper Methods

    /// 检查是否在 CI 环境中运行
    private func isRunningInCI() -> Bool {
        // 检查常见的 CI 环境变量
        let ciVariables = ["CI", "GITHUB_ACTIONS", "GITLAB_CI", "JENKINS_URL", "TRAVIS"]
        return ciVariables.contains { ProcessInfo.processInfo.environment[$0] != nil }
    }

    /// 从 Keychain 删除测试凭据
    private func deleteKeychainCredential(for urlString: String) {
        guard let url = URL(string: urlString) else { return }

        let host = url.host ?? urlString
        let `protocol` = url.scheme ?? "https"

        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrProtocol as String: `protocol`
        ]

        // 删除匹配的所有项
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Network Credential Tests

extension CredentialTests {
    func testPushWithCredential() async throws {
        // 跳过在 CI 环境中的测试
        try XCTSkipIf(isRunningInCI(), "Network tests skipped in CI environment")

        // 这个测试需要真实的远程仓库和凭据
        // 在实际环境中应该使用 mock 或者测试仓库
        // 这里只演示测试结构

        // TODO: 实现 mock credential 环境
        // 或者使用测试仓库进行集成测试
        throw XCTSkip("Push with credential test requires mock setup or real repository")
    }

    func testPullWithCredential() async throws {
        // 跳过在 CI 环境中的测试
        try XCTSkipIf(isRunningInCI(), "Network tests skipped in CI environment")

        // 同上，需要 mock 或真实环境
        throw XCTSkip("Pull with credential test requires mock setup or real repository")
    }
}

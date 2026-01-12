import Foundation
@testable import LibGit2Swift
import XCTest

/// Remote 相关功能的测试
final class RemoteTests: LibGit2SwiftTestCase {
    // MARK: - Add Remote Tests

    func testAddRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        let remoteName = "origin"
        let remoteURL = "https://github.com/test/repo.git"
        try LibGit2.addRemote(name: remoteName, url: remoteURL, at: testRepo.repositoryPath)

        // 验证远程仓库已添加
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        XCTAssertTrue(remotes.contains { $0.name == remoteName },
                      "Remote list should contain the newly added remote")
    }

    func testAddMultipleRemotes() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加多个远程仓库
        let remotes = [
            ("origin", "https://github.com/test/repo.git"),
            ("upstream", "https://github.com/original/repo.git"),
            ("backup", "https://gitlab.com/test/repo.git")
        ]

        for (name, url) in remotes {
            try LibGit2.addRemote(name: name, url: url, at: testRepo.repositoryPath)
        }

        // 验证所有远程仓库都已添加
        let remoteList = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remoteNames = remoteList.map { $0.name }

        for (name, _) in remotes {
            XCTAssertTrue(remoteNames.contains(name),
                          "Remote '\(name)' should be in the remote list")
        }
    }

    func testAddDuplicateRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        let remoteName = "origin"
        try LibGit2.addRemote(name: remoteName, url: "https://github.com/test/repo.git",
                             at: testRepo.repositoryPath)

        // 尝试添加同名远程仓库应该失败
        XCTAssertThrowsError(
            try LibGit2.addRemote(name: remoteName, url: "https://github.com/other/repo.git",
                                  at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for duplicate remote")
        }
    }

    // MARK: - Delete Remote Tests

    func testDeleteRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        let remoteName = "origin"
        try LibGit2.addRemote(name: remoteName, url: "https://github.com/test/repo.git",
                             at: testRepo.repositoryPath)

        // 删除远程仓库
        try LibGit2.removeRemote(name: remoteName, at: testRepo.repositoryPath)

        // 验证远程仓库已删除
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remoteNames = remotes.map { $0.name }

        XCTAssertFalse(remoteNames.contains(remoteName),
                       "Remote list should not contain the deleted remote")
    }

    func testDeleteNonExistentRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let nonExistentRemote = "nonexistent_remote"

        // 尝试删除不存在的远程仓库应该失败
        XCTAssertThrowsError(
            try LibGit2.removeRemote(name: nonExistentRemote, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for non-existent remote")
        }
    }

    // MARK: - Rename Remote Tests

    func testRenameRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        let oldName = "origin"
        let newName = "upstream"
        try LibGit2.addRemote(name: oldName, url: "https://github.com/test/repo.git",
                             at: testRepo.repositoryPath)

        // 重命名远程仓库
        try LibGit2.renameRemote(oldName: oldName, to: newName, at: testRepo.repositoryPath)

        // 验证远程仓库已重命名
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remoteNames = remotes.map { $0.name }

        XCTAssertFalse(remoteNames.contains(oldName),
                       "Old remote name should not exist")
        XCTAssertTrue(remoteNames.contains(newName),
                      "New remote name should exist")
    }

    func testRenameNonExistentRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let oldName = "nonexistent"
        let newName = "newname"

        // 尝试重命名不存在的远程仓库应该失败
        XCTAssertThrowsError(
            try LibGit2.renameRemote(oldName: oldName, to: newName, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for non-existent remote")
        }
    }

    // MARK: - Set Remote URL Tests

    func testSetRemoteURL() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        let remoteName = "origin"
        let originalURL = "https://github.com/test/repo.git"
        try LibGit2.addRemote(name: remoteName, url: originalURL, at: testRepo.repositoryPath)

        // 更新远程仓库 URL
        let newURL = "https://gitlab.com/test/repo.git"
        try LibGit2.setRemoteURL(name: remoteName, url: newURL, at: testRepo.repositoryPath)

        // 验证 URL 已更新
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remote = remotes.first { $0.name == remoteName }

        XCTAssertNotNil(remote, "Remote should exist")
        XCTAssertEqual(remote?.url, newURL, "Remote URL should be updated")
    }

    func testSetRemoteURLNonExistentRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let nonExistentRemote = "nonexistent"

        // 尝试更新不存在远程的 URL 应该失败
        XCTAssertThrowsError(
            try LibGit2.setRemoteURL(name: nonExistentRemote,
                                     url: "https://github.com/test/repo.git",
                                     at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for non-existent remote")
        }
    }

    // MARK: - Get Remote List Tests

    func testGetRemoteListEmpty() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 没有添加远程仓库时，列表应该为空
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        XCTAssertTrue(remotes.isEmpty, "Remote list should be empty when no remotes added")
    }

    func testGetRemoteList() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        try testRepo.addRemote(name: "origin", url: "https://github.com/test/repo.git")

        // 获取远程仓库列表
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)

        XCTAssertEqual(remotes.count, 1, "Should have exactly one remote")

        let remote = remotes.first
        XCTAssertEqual(remote?.name, "origin", "Remote name should be 'origin'")
        XCTAssertEqual(remote?.url, "https://github.com/test/repo.git", "Remote URL should match")
        XCTAssertTrue(remote?.isDefault ?? false, "First remote should be marked as default")
    }

    // MARK: - Remote Properties Tests

    func testRemoteProperties() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        try LibGit2.addRemote(name: "origin", url: "https://github.com/test/repo.git",
                             at: testRepo.repositoryPath)

        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        guard let remote = remotes.first else {
            XCTFail("Should have at least one remote")
            return
        }

        // 验证必需属性
        XCTAssertFalse(remote.id.isEmpty, "Remote ID should not be empty")
        XCTAssertFalse(remote.name.isEmpty, "Remote name should not be empty")
        XCTAssertFalse(remote.url.isEmpty, "Remote URL should not be empty")
        XCTAssertNotNil(remote.fetchURL, "Fetch URL should not be nil")
        XCTAssertNotNil(remote.pushURL, "Push URL should not be nil")
    }

    // MARK: - Get Remote URL Tests

    func testGetRemoteURL() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        let remoteName = "origin"
        let remoteURL = "https://github.com/test/repo.git"
        try LibGit2.addRemote(name: remoteName, url: remoteURL, at: testRepo.repositoryPath)

        // 获取远程仓库 URL
        let retrievedURL = try LibGit2.getRemoteURL(name: remoteName, at: testRepo.repositoryPath)

        XCTAssertEqual(retrievedURL, remoteURL, "Retrieved URL should match the original URL")
    }

    func testGetRemoteURLNonExistentRemote() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let nonExistentRemote = "nonexistent"

        // 尝试获取不存在远程的 URL 应该失败
        XCTAssertThrowsError(
            try LibGit2.getRemoteURL(name: nonExistentRemote, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for non-existent remote")
        }
    }

    // MARK: - Error Handling Tests

    func testAddRemoteWithInvalidURL() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // libgit2 可能会接受任何格式的 URL，不会验证 URL 的有效性
        // 这里我们测试方法不会崩溃
        XCTAssertNoThrow(
            try LibGit2.addRemote(name: "test", url: "not-a-valid-url", at: testRepo.repositoryPath)
        )
    }

    func testAddRemoteWithEmptyName() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 尝试添加空名称的远程仓库应该失败
        XCTAssertThrowsError(
            try LibGit2.addRemote(name: "", url: "https://github.com/test/repo.git",
                                  at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for empty remote name")
        }
    }

    // MARK: - SSH Remote Tests

    func testAddSSHRemote() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加 SSH 格式的远程仓库（SCP-like）
        let sshURL = "git@github.com:test/repo.git"
        try LibGit2.addRemote(name: "origin", url: sshURL, at: testRepo.repositoryPath)

        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remote = remotes.first { $0.name == "origin" }

        XCTAssertNotNil(remote, "SSH remote should be added")
        XCTAssertEqual(remote?.url, sshURL, "SSH URL should be preserved")
    }

    func testAddSSHRemoteWithProtocol() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加带协议前缀的 SSH URL
        let sshURL = "ssh://git@github.com/test/repo.git"
        try LibGit2.addRemote(name: "origin", url: sshURL, at: testRepo.repositoryPath)

        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remote = remotes.first { $0.name == "origin" }

        XCTAssertNotNil(remote, "SSH remote with protocol should be added")
        XCTAssertEqual(remote?.url, sshURL, "SSH URL with protocol should be preserved")
    }

    func testMixedRemoteProtocols() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加不同协议的远程仓库
        let remotes = [
            ("origin", "https://github.com/test/repo.git", "HTTPS"),
            ("upstream", "git@github.com:original/repo.git", "SSH (SCP-like)"),
            ("mirror", "ssh://git@gitlab.com/test/repo.git", "SSH (with protocol)"),
            ("backup", "git://github.com/test/repo.git", "Git protocol")
        ]

        for (name, url, _) in remotes {
            try LibGit2.addRemote(name: name, url: url, at: testRepo.repositoryPath)
        }

        let remoteList = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        XCTAssertEqual(remoteList.count, 4, "Should have all four remotes")

        // 验证每个远程的 URL
        for (name, url, protocolType) in remotes {
            let retrievedURL = try LibGit2.getRemoteURL(name: name, at: testRepo.repositoryPath)
            XCTAssertEqual(retrievedURL, url, "\(protocolType) URL for '\(name)' should match")
        }
    }

    func testSSHRemoteURLPersistence() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加 SSH 远程
        let originalSSHURL = "git@github.com:test/repo.git"
        try LibGit2.addRemote(name: "origin", url: originalSSHURL, at: testRepo.repositoryPath)

        // 更新为不同的 SSH URL
        let newSSHURL = "git@gitlab.com:test/repo.git"
        try LibGit2.setRemoteURL(name: "origin", url: newSSHURL, at: testRepo.repositoryPath)

        // 验证 URL 已更新
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remote = remotes.first { $0.name == "origin" }

        XCTAssertNotNil(remote, "Remote should exist")
        XCTAssertEqual(remote?.url, newSSHURL, "Remote URL should be updated to new SSH URL")
        XCTAssertNotEqual(remote?.url, originalSSHURL, "Remote URL should not be the old SSH URL")
    }

    func testSSHRemoteInRemoteList() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加多个 SSH 远程
        let sshRemotes = [
            ("origin", "git@github.com:test/repo.git"),
            ("gitlab", "git@gitlab.com:test/repo.git"),
            ("bitbucket", "git@bitbucket.org:test/repo.git")
        ]

        for (name, url) in sshRemotes {
            try LibGit2.addRemote(name: name, url: url, at: testRepo.repositoryPath)
        }

        // 获取远程列表并验证
        let remoteList = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        XCTAssertEqual(remoteList.count, 3, "Should have all three SSH remotes")

        // 验证每个 SSH 远程的属性
        for (name, url) in sshRemotes {
            let remote = remoteList.first { $0.name == name }
            XCTAssertNotNil(remote, "SSH remote '\(name)' should exist")
            XCTAssertEqual(remote?.url, url, "SSH remote '\(name)' URL should match")
            XCTAssertEqual(remote?.fetchURL, url, "SSH remote '\(name)' fetch URL should match")
            XCTAssertEqual(remote?.pushURL, url, "SSH remote '\(name)' push URL should match")

            // 验证 isDefault 标志
            if name == "origin" {
                XCTAssertTrue(remote?.isDefault ?? false, "origin remote should be marked as default")
            }
        }
    }

    func testDeleteSSHRemote() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加 SSH 远程
        let sshURL = "git@github.com:test/repo.git"
        try LibGit2.addRemote(name: "origin", url: sshURL, at: testRepo.repositoryPath)

        // 删除远程
        try LibGit2.removeRemote(name: "origin", at: testRepo.repositoryPath)

        // 验证已删除
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remoteNames = remotes.map { $0.name }

        XCTAssertFalse(remoteNames.contains("origin"), "SSH remote should be deleted")
    }

    func testRenameSSHRemote() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加 SSH 远程
        let sshURL = "git@github.com:test/repo.git"
        try LibGit2.addRemote(name: "origin", url: sshURL, at: testRepo.repositoryPath)

        // 重命名
        try LibGit2.renameRemote(oldName: "origin", to: "upstream", at: testRepo.repositoryPath)

        // 验证重命名
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        let remoteNames = remotes.map { $0.name }

        XCTAssertFalse(remoteNames.contains("origin"), "Old name should not exist")
        XCTAssertTrue(remoteNames.contains("upstream"), "New name should exist")

        // 验证 URL 保持不变
        let renamedRemote = remotes.first { $0.name == "upstream" }
        XCTAssertEqual(renamedRemote?.url, sshURL, "URL should remain the same after rename")
    }

    func testSSHRemoteURLExtraction() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 测试不同格式的 SSH URL
        let sshURLs = [
            "git@github.com:test/repo.git",
            "ssh://git@github.com/test/repo.git",
            "git@gitlab.com:test/repo.git"
        ]

        for (index, sshURL) in sshURLs.enumerated() {
            let remoteName = "remote\(index)"
            try LibGit2.addRemote(name: remoteName, url: sshURL, at: testRepo.repositoryPath)

            // 获取并验证 URL
            let retrievedURL = try LibGit2.getRemoteURL(name: remoteName, at: testRepo.repositoryPath)
            XCTAssertEqual(retrievedURL, sshURL, "SSH URL '\(sshURL)' should be retrieved correctly")
        }
    }

    // MARK: - Complex Scenarios

    func testMultipleRemotesWithDifferentNames() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加多个远程仓库，验证它们独立工作
        let remotes = [
            ("origin", "https://github.com/test/repo.git"),
            ("fork", "https://github.com/myfork/repo.git"),
            ("mirror", "https://gitlab.com/test/repo.git")
        ]

        for (name, url) in remotes {
            try LibGit2.addRemote(name: name, url: url, at: testRepo.repositoryPath)
        }

        // 验证每个远程仓库的 URL
        for (name, url) in remotes {
            let retrievedURL = try LibGit2.getRemoteURL(name: name, at: testRepo.repositoryPath)
            XCTAssertEqual(retrievedURL, url, "URL for '\(name)' should match")
        }

        // 重命名一个远程仓库
        try LibGit2.renameRemote(oldName: "fork", to: "upstream", at: testRepo.repositoryPath)

        // 验证重命名后的远程存在，旧的不存在
        XCTAssertNoThrow(
            try LibGit2.getRemoteURL(name: "upstream", at: testRepo.repositoryPath)
        )

        XCTAssertThrowsError(
            try LibGit2.getRemoteURL(name: "fork", at: testRepo.repositoryPath)
        )

        // 删除一个远程仓库
        try LibGit2.removeRemote(name: "mirror", at: testRepo.repositoryPath)

        // 验证远程仓库数量
        let remainingRemotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        XCTAssertEqual(remainingRemotes.count, 2, "Should have 2 remotes after deletion")
    }
}

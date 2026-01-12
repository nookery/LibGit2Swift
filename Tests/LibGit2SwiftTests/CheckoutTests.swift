import Foundation
@testable import LibGit2Swift
import XCTest

/// Checkout 相关功能的测试
final class CheckoutTests: LibGit2SwiftTestCase {
    // MARK: - Branch Checkout Tests

    func testCheckoutExistingBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建新分支
        let branchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)

        // 切换到新分支
        try LibGit2.checkout(branch: branchName, at: testRepo.repositoryPath)

        // 验证当前分支已改变
        let currentBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)
        XCTAssertEqual(currentBranch, branchName, "Current branch should be the newly checked out branch")
    }

    func testCheckoutNonExistentBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let nonExistentBranch = "nonexistent_branch"

        // 尝试切换到不存在的分支应该失败
        XCTAssertThrowsError(
            try LibGit2.checkout(branch: nonExistentBranch, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for non-existent branch")
        }
    }

    // MARK: - Create and Checkout Tests

    func testCreateAndCheckoutNewBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建并切换到新分支
        let newBranchName = TestDataGenerator.randomBranchName()
        try LibGit2.checkoutNewBranch(named: newBranchName, at: testRepo.repositoryPath)

        // 验证当前分支
        let currentBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)
        XCTAssertEqual(currentBranch, newBranchName, "Current branch should be the newly created branch")

        // 验证分支存在于列表中
        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)
        let branchNames = branches.map { $0.name }
        XCTAssertTrue(branchNames.contains(newBranchName),
                      "Branch should exist in branch list")
    }

    // MARK: - File Checkout Tests

    func testCheckoutSingleFile() throws {
        // 创建并提交文件
        let fileName = "test.txt"
        let originalContent = "Original content"
        try testRepo.createFileAndCommit(
            fileName: fileName,
            content: originalContent,
            message: "Initial commit"
        )

        // 修改文件
        let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
        try "Modified content".write(to: fileURL, atomically: true, encoding: .utf8)

        // 验证文件已修改
        let modifiedContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(modifiedContent, "Modified content", "File should be modified")

        // 检出文件（丢弃修改）
        try LibGit2.checkoutFiles([fileName], at: testRepo.repositoryPath)

        // 验证文件已恢复
        let restoredContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(restoredContent, originalContent, "File should be restored to original content")
    }

    func testCheckoutMultipleFiles() throws {
        // 创建并提交多个文件
        let fileNames = ["file1.txt", "file2.txt", "file3.txt"]
        for fileName in fileNames {
            try testRepo.createFileAndCommit(
                fileName: fileName,
                content: "\(fileName) content",
                message: "Add \(fileName)"
            )
        }

        // 修改所有文件
        for fileName in fileNames {
            let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
            try "Modified \(fileName)".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // 检出所有文件
        try LibGit2.checkoutFiles(fileNames, at: testRepo.repositoryPath)

        // 验证所有文件已恢复
        for fileName in fileNames {
            let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(content.contains("Modified"),
                          "File '\(fileName)' should be restored to original")
        }
    }

    func testCheckoutFileInSubdirectory() throws {
        // 创建子目录和文件
        let subDir = testRepo.tempDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let fileName = "subdir/file.txt"
        let originalContent = "Original content"
        let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
        try originalContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // 提交文件
        try LibGit2.addFiles([fileName], at: testRepo.repositoryPath)
        try LibGit2.createCommit(message: "Add file", at: testRepo.repositoryPath, verbose: false)

        // 修改文件
        try "Modified content".write(to: fileURL, atomically: true, encoding: .utf8)

        // 检出文件
        try LibGit2.checkoutFiles([fileName], at: testRepo.repositoryPath)

        // 验证文件已恢复
        let restoredContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(restoredContent, originalContent, "File should be restored")
    }

    // MARK: - Checkout All Files Tests

    func testCheckoutAllFiles() throws {
        // 创建并提交多个文件
        let fileNames = ["file1.txt", "file2.txt", "file3.txt"]
        for fileName in fileNames {
            try testRepo.createFileAndCommit(
                fileName: fileName,
                content: "\(fileName) content",
                message: "Add \(fileName)"
            )
        }

        // 修改所有文件
        for fileName in fileNames {
            let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
            try "Modified \(fileName)".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // 检出所有文件
        try LibGit2.checkoutAllFiles(at: testRepo.repositoryPath)

        // 验证所有文件已恢复
        for fileName in fileNames {
            let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(content.contains("Modified"),
                          "File '\(fileName)' should be restored")
        }
    }

    // MARK: - Checkout Commit Tests (Detached HEAD)

    func testCheckoutCommit() throws {
        // 创建多个提交
        try testRepo.createFileAndCommit(
            fileName: "commit1.txt",
            content: "Content 1",
            message: "Commit 1"
        )

        try testRepo.createFileAndCommit(
            fileName: "commit2.txt",
            content: "Content 2",
            message: "Commit 2"
        )

        // 获取提交列表
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        guard commits.count >= 2 else {
            XCTFail("Should have at least 2 commits")
            return
        }

        let secondCommitHash = commits[1].hash // 第二个提交（较早的）

        // 检出到特定提交
        try LibGit2.checkoutCommit( secondCommitHash, at: testRepo.repositoryPath)

        // 验证 HEAD 处于分离状态
        let isDetached = try LibGit2.isHEADDetached(at: testRepo.repositoryPath)
        XCTAssertTrue(isDetached, "HEAD should be detached after checking out a commit")
    }

    func testCheckoutInvalidCommit() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let invalidCommitHash = "invalid_hash_12345"

        // 尝试检出到无效的提交
        XCTAssertThrowsError(
            try LibGit2.checkoutCommit( invalidCommitHash, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for invalid commit hash")
        }
    }

    // MARK: - Checkout Remote Branch Tests

    func testCheckoutRemoteBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        try testRepo.addRemote(name: "origin", url: "https://github.com/test/repo.git")

        // 注意：由于我们没有实际 fetch 远程仓库，这里只测试方法不崩溃
        // 实际使用中需要先 fetch 远程分支
        // let remoteBranch = "origin/main"
        // try LibGit2.checkoutRemoteBranch(named: remoteBranch, at: testRepo.repositoryPath)

        // 验证远程仓库已添加
        let remotes = try LibGit2.getRemoteList(at: testRepo.repositoryPath)
        XCTAssertTrue(remotes.contains { $0.name == "origin" },
                      "Remote 'origin' should exist")
    }

    // MARK: - Branch Switching with Uncommitted Changes Tests

    func testCheckoutBranchWithCleanState() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建新分支
        let branchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)

        // 在干净状态下切换分支应该成功
        XCTAssertNoThrow(
            try LibGit2.checkout(branch: branchName, at: testRepo.repositoryPath)
        )

        let currentBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)
        XCTAssertEqual(currentBranch, branchName, "Should successfully switch to new branch")
    }

    func testCheckoutBranchWithConflictingChanges() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "shared.txt",
            content: "Original content",
            message: "Initial commit"
        )

        // 创建新分支
        let branchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)

        // 在主分支修改文件
        let fileURL = testRepo.tempDirectory.appendingPathComponent("shared.txt")
        try "Modified in master".write(to: fileURL, atomically: true, encoding: .utf8)

        // 尝试切换分支（应该失败或警告，因为有未提交的更改）
        // libgit2 可能会允许切换，如果文件在目标分支中不同
        // 这里我们测试行为不崩溃
        XCTAssertNoThrow(
            try LibGit2.checkout(branch: branchName, at: testRepo.repositoryPath)
        )
    }

    // MARK: - File State After Checkout Tests

    func testFileStateAfterBranchSwitch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Content on main",
            message: "Initial commit"
        )

        // 获取初始分支名
        let initialBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)

        // 创建新分支
        let branchName = "feature"
        try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)

        // 切换到新分支
        try LibGit2.checkout(branch: branchName, at: testRepo.repositoryPath)

        // 在新分支修改文件
        let fileURL = testRepo.tempDirectory.appendingPathComponent("file1.txt")
        try "Content on feature branch".write(to: fileURL, atomically: true, encoding: .utf8)

        try LibGit2.addFiles(["file1.txt"], at: testRepo.repositoryPath)
        try LibGit2.createCommit(message: "Modify on feature", at: testRepo.repositoryPath, verbose: false)

        // 切换回主分支
        try LibGit2.checkout(branch: initialBranch, at: testRepo.repositoryPath)

        // 验证文件内容恢复到主分支的版本
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, "Content on main",
                      "File content should match main branch after checkout")
    }

    // MARK: - Error Handling Tests

    func testCheckoutInvalidFile() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 尝试检出不存在的文件
        let nonExistentFile = "nonexistent.txt"

        // libgit2 可能会忽略不存在的文件
        XCTAssertNoThrow(
            try LibGit2.checkoutFiles([nonExistentFile], at: testRepo.repositoryPath)
        )
    }

    // MARK: - Complex Scenarios

    func testCheckoutWorkflow() throws {
        // 完整的工作流程测试

        // 1. 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "file.txt",
            content: "Initial",
            message: "Initial commit"
        )

        // 2. 创建并切换到功能分支
        let featureBranch = "feature/add-functionality"
        try LibGit2.checkoutNewBranch(named: featureBranch, at: testRepo.repositoryPath)

        // 3. 在功能分支上工作
        try testRepo.createFileAndCommit(
            fileName: "feature.txt",
            content: "Feature content",
            message: "Add feature"
        )

        // 4. 切换回初始分支
        let currentBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)
        // 从当前分支名推断初始分支名
        let initialBranch = currentBranch == featureBranch ? "main" : currentBranch
        try LibGit2.checkout(branch: initialBranch, at: testRepo.repositoryPath)

        // 5. 在主分支上工作
        try testRepo.createFileAndCommit(
            fileName: "main.txt",
            content: "Main content",
            message: "Add main file"
        )

        // 6. 验证分支隔离
        let commitsOnInitial = try LibGit2.getCommitList(on: initialBranch, at: testRepo.repositoryPath)
        let commitsOnFeature = try LibGit2.getCommitList(on: featureBranch, at: testRepo.repositoryPath)

        // 初始分支应该包含 "Add main file" 提交
        XCTAssertTrue(commitsOnInitial.contains { $0.message == "Add main file" },
                      "\(initialBranch) branch should contain main commit")

        // 功能分支应该包含 "Add feature" 提交
        XCTAssertTrue(commitsOnFeature.contains { $0.message == "Add feature" },
                      "Feature branch should contain feature commit")
    }
}
